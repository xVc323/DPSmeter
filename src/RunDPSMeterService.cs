using System.Globalization;
using System.Text.Json;
using System.Threading;
using Godot;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Models;
using MegaCrit.Sts2.Core.Models.Powers;

namespace DPSMeter;

public static class RunDPSMeterService
{
    private static readonly object SyncRoot = new();
    private static readonly Dictionary<ulong, PlayerDamageSnapshot> Totals = new();
    private static readonly string SavePath = ProjectSettings.GlobalizePath("user://dps_meter_state.json");

    private static string? _currentRunToken;
    private static string? _stableRunId;
    private static int _combatIndex;
    private static bool _combatActive;
    private static ulong? _activePlayerKey;
    private static int _damageCounter;
    private static readonly AsyncLocal<PoisonTrackingContext?> CurrentPoisonContext = new();
    private static readonly AsyncLocal<CardDamageAggregationContext?> CurrentCardDamageAggregation = new();
    private static readonly Dictionary<Creature, PendingDoomDamage> PendingDoomDamageByCreature = new();

    public static event Action<OverlayState>? Changed;

    public static void BeginRun(object? runState)
    {
        string nextToken = ReflectionHelpers.ResolveRunToken(runState);
        string stableId = ReflectionHelpers.ResolveStableRunId(runState);
        List<PlayerHandle> knownPlayers = CollectKnownPlayers(runState);
        bool shouldPublish;

        lock (SyncRoot)
        {
            // Same token in memory — skip
            if (string.Equals(_currentRunToken, nextToken, StringComparison.Ordinal))
            {
                shouldPublish = RegisterKnownPlayers(knownPlayers);
            }

            // Same stable ID (e.g. after save & quit) — keep accumulated data
            else if (!string.IsNullOrEmpty(stableId) &&
                     string.Equals(_stableRunId, stableId, StringComparison.Ordinal))
            {
                _currentRunToken = nextToken;
                shouldPublish = RegisterKnownPlayers(knownPlayers);
            }

            // Try restoring from disk if stable ID matches
            else if (!string.IsNullOrEmpty(stableId) && TryLoadState(stableId))
            {
                _currentRunToken = nextToken;
                _stableRunId = stableId;
                shouldPublish = RegisterKnownPlayers(knownPlayers) || true;
            }

            // Truly new run — reset everything
            else
            {
                Totals.Clear();
                PendingDoomDamageByCreature.Clear();
                _currentRunToken = nextToken;
                _stableRunId = stableId;
                _combatIndex = 0;
                _combatActive = false;
                _activePlayerKey = null;
                _damageCounter = 0;

                RegisterKnownPlayers(knownPlayers);
                shouldPublish = true;
            }
        }

        if (shouldPublish)
            Publish();
    }

    public static void BeginCombat(object? runState, object? combatState)
    {
        List<PlayerHandle> knownPlayers = CollectKnownPlayers(runState, combatState);

        SaveState();

        lock (SyncRoot)
        {
            _combatIndex++;
            _combatActive = combatState != null;
            _activePlayerKey = null;
            PendingDoomDamageByCreature.Clear();

            RegisterKnownPlayers(knownPlayers);

            foreach (PlayerDamageSnapshot snapshot in Totals.Values)
            {
                snapshot.CombatDamage = 0m;
                snapshot.CardsPlayed = 0;
                snapshot.AttackCardsPlayed = 0;
                snapshot.SkillCardsPlayed = 0;
                snapshot.PowerCardsPlayed = 0;
                snapshot.OtherCardsPlayed = 0;
                snapshot.AutoCardsPlayed = 0;
                snapshot.IncomingDamage = 0m;
                snapshot.BlockedDamage = 0m;
                snapshot.HpLostDamage = 0m;
                snapshot.LastDamageReceived = 0m;
                snapshot.MaxDamageReceived = 0m;
                snapshot.BlockGained = 0m;
                snapshot.IsActive = false;
            }
        }

        Publish();
    }

    public static void RecordCardPlayed(CardPlay? cardPlay)
    {
        CardModel? card = cardPlay?.Card;
        if (card == null)
        {
            return;
        }

        if (!ReflectionHelpers.TryResolvePlayerHandle(card, out PlayerHandle handle))
        {
            return;
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            snapshot.CardsPlayed++;
            if (cardPlay!.IsAutoPlay)
            {
                snapshot.AutoCardsPlayed++;
            }

            switch (card.Type)
            {
                case CardType.Attack:
                    snapshot.AttackCardsPlayed++;
                    break;
                case CardType.Skill:
                    snapshot.SkillCardsPlayed++;
                    break;
                case CardType.Power:
                    snapshot.PowerCardsPlayed++;
                    break;
                default:
                    snapshot.OtherCardsPlayed++;
                    break;
            }

            snapshot.LastUpdatedUtc = DateTime.UtcNow;
        }

        Publish();
    }

    public static void BeginCardDamageAggregation(CardPlay? cardPlay)
    {
        CardModel? card = cardPlay?.Card;
        if (card == null)
        {
            return;
        }

        if (!ReflectionHelpers.TryResolvePlayerHandle(card, out PlayerHandle handle))
        {
            return;
        }

        CurrentCardDamageAggregation.Value = new CardDamageAggregationContext(cardPlay!, handle, CurrentCardDamageAggregation.Value);
    }

    public static void CompleteCardDamageAggregation(CardPlay? cardPlay)
    {
        CardDamageAggregationContext? context = CurrentCardDamageAggregation.Value;
        if (context == null)
        {
            return;
        }

        if (cardPlay != null && !ReferenceEquals(context.CardPlay, cardPlay))
        {
            return;
        }

        decimal aggregateDamage = context.Damage;
        PlayerHandle handle = context.Handle;
        CurrentCardDamageAggregation.Value = context.Previous;

        if (aggregateDamage <= 0m)
        {
            return;
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            snapshot.LastDamage = aggregateDamage;
            if (aggregateDamage > snapshot.MaxHitDamage)
                snapshot.MaxHitDamage = aggregateDamage;
            snapshot.LastUpdatedUtc = DateTime.UtcNow;
        }

        Publish();
    }

    public static void RecordDamageReceived(Creature? target, DamageResult? result)
    {
        if (target == null || result == null || !ReflectionHelpers.IsPlayerCreature(target))
        {
            return;
        }

        if (!ReflectionHelpers.TryResolvePlayerHandle(target, out PlayerHandle handle))
        {
            return;
        }

        decimal incoming = result.TotalDamage;
        decimal blocked = result.BlockedDamage;
        decimal hpLost = result.UnblockedDamage;

        if (incoming <= 0m && blocked <= 0m && hpLost <= 0m)
        {
            return;
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            snapshot.IncomingDamage += incoming;
            snapshot.BlockedDamage += blocked;
            snapshot.HpLostDamage += hpLost;
            snapshot.LastDamageReceived = hpLost;
            if (hpLost > snapshot.MaxDamageReceived)
                snapshot.MaxDamageReceived = hpLost;
            snapshot.LastUpdatedUtc = DateTime.UtcNow;
        }

        Publish();
    }

    public static void RecordBlockGained(Creature? creature, decimal amount)
    {
        if (creature == null || amount <= 0m || !ReflectionHelpers.IsPlayerCreature(creature))
        {
            return;
        }

        if (!ReflectionHelpers.TryResolvePlayerHandle(creature, out PlayerHandle handle))
        {
            return;
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            snapshot.BlockGained += amount;
            snapshot.LastUpdatedUtc = DateTime.UtcNow;
        }

        Publish();
    }

    public static void EnsurePlayersRegistered(params object?[] sources)
    {
        List<PlayerHandle> knownPlayers = CollectKnownPlayers(sources);
        if (knownPlayers.Count == 0)
            return;

        bool shouldPublish;
        lock (SyncRoot)
        {
            shouldPublish = RegisterKnownPlayers(knownPlayers);
        }

        if (shouldPublish)
            Publish();
    }


    public static void EndRun()
    {
        lock (SyncRoot)
        {
            Totals.Clear();
            PendingDoomDamageByCreature.Clear();
            _currentRunToken = null;
            _stableRunId = null;
            _combatIndex = 0;
            _combatActive = false;
            _activePlayerKey = null;
            _damageCounter = 0;
            CurrentPoisonContext.Value = null;
            CurrentCardDamageAggregation.Value = null;
        }

        DeletePersistedState();
        Publish();
    }

    public static void EndCombat()
    {
        lock (SyncRoot)
        {
            _combatActive = false;
            _activePlayerKey = null;

            foreach (PlayerDamageSnapshot snapshot in Totals.Values)
            {
                snapshot.IsActive = false;
            }
        }

        SaveState();
        Publish();
    }

    public static void NotePlayer(object? player)
    {
        if (!ReflectionHelpers.TryResolvePlayerHandle(player, out PlayerHandle handle))
        {
            return;
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            _activePlayerKey = handle.PlayerKey;

            foreach (PlayerDamageSnapshot playerSnapshot in Totals.Values)
            {
                playerSnapshot.IsActive = playerSnapshot.PlayerKey == handle.PlayerKey;
            }
        }

        Publish();
    }

    public static void RecordDamage(object? dealer, object? result, object? target, object? cardSource)
    {
        if (!ReflectionHelpers.TryResolveDamageAmount(result, out decimal damage) || damage <= 0)
        {
            return;
        }

        if (!ReflectionHelpers.TryResolvePlayerHandle(dealer, out PlayerHandle handle))
        {
            if (!ReflectionHelpers.TryResolvePlayerHandle(cardSource, out handle))
            {
                return;
            }
        }

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            ApplyHandle(snapshot, handle);
            snapshot.TotalDamage += damage;
            snapshot.CombatDamage += damage;
            snapshot.LastDamage = damage;
            bool groupedIntoCardPlay = TryAddToActiveCardDamageAggregation(handle.PlayerKey, damage);
            if (!groupedIntoCardPlay && damage > snapshot.MaxHitDamage)
                snapshot.MaxHitDamage = damage;
            snapshot.LastUpdatedUtc = DateTime.UtcNow;
            _damageCounter++;
        }

        if (_damageCounter % 10 == 0)
            SaveState();

        Publish();
    }

    public static void RecordDoomDamage(CombatState combatState, System.Collections.Generic.IReadOnlyList<Creature>? creatures)
    {
        if (creatures == null) return;
        
        try
        {
            foreach (var creature in creatures)
            {
                if (creature == null) continue;

                PendingDoomDamage? pending = null;
                lock (SyncRoot)
                {
                    if (PendingDoomDamageByCreature.TryGetValue(creature, out PendingDoomDamage? captured))
                    {
                        pending = captured;
                        PendingDoomDamageByCreature.Remove(creature);
                    }
                }

                if (pending != null && pending.Damage > 0)
                {
                    RecordStatusDamage(pending.Applier, pending.Damage, creature, "Doom");
                }
            }
        }
        catch (System.Exception ex)
        {
            GD.PrintErr($"[DPSMeter] RecordDoomDamage error: {ex.Message}");
        }
    }

    public static object? BeginPoisonTracking(PoisonPower poisonPower, CombatSide side)
    {
        if (poisonPower.Owner == null || side != poisonPower.Owner.Side)
        {
            return null;
        }

        Creature? applier = poisonPower.Applier;
        if (applier == null || !ReflectionHelpers.IsPlayerCreature(applier))
        {
            return null;
        }

        PoisonTrackingContext context = new(poisonPower.Owner, applier, CurrentPoisonContext.Value);
        CurrentPoisonContext.Value = context;
        return context;
    }

    public static Task CompletePoisonTrackingAsync(Task originalTask, object? state)
    {
        if (state is not PoisonTrackingContext context)
        {
            return originalTask;
        }

        return AwaitAndRestorePoisonContextAsync(originalTask, context);
    }

    public static bool TryRecordPoisonDamage(object? dealer, object? target, object? cardSource, object? result)
    {
        PoisonTrackingContext? context = CurrentPoisonContext.Value;
        if (context == null || dealer != null || cardSource != null || !ReferenceEquals(context.Target, target))
        {
            return false;
        }

        if (!ReflectionHelpers.TryResolveDamageAmount(result, out decimal damage) || damage <= 0)
        {
            return false;
        }

        RecordStatusDamage(context.Applier, damage, target, "Poison");
        return true;
    }

    public static void CapturePendingDoomDamage(System.Collections.Generic.IReadOnlyList<Creature> creatures)
    {
        lock (SyncRoot)
        {
            foreach (Creature creature in creatures)
            {
                DoomPower? doom = creature.GetPower<DoomPower>();
                Creature? applier = doom?.Applier;
                if (creature.CurrentHp <= 0 || applier == null || !ReflectionHelpers.IsPlayerCreature(applier))
                {
                    continue;
                }

                PendingDoomDamageByCreature[creature] = new PendingDoomDamage(applier, creature.CurrentHp);
            }
        }
    }

    /// <summary>
    /// Records status damage such as Poison and Doom for the owning player.
    /// </summary>
    private static void RecordStatusDamage(object? applier, decimal damage, object? target, string damageType)
    {
        if (damage <= 0) return;
        
        PlayerHandle? handle = null;
        
        // Try to resolve the player handle from the applier.
        if (applier != null)
        {
            if (ReflectionHelpers.TryResolvePlayerHandle(applier, out var h))
            {
                handle = h;
            }
        }
        
        // If no player applier is available, fall back to current active player context.
        if (handle == null)
        {
            // Try the current active player.
            lock (SyncRoot)
            {
                if (_activePlayerKey.HasValue && Totals.TryGetValue(_activePlayerKey.Value, out var snap))
                {
                    handle = new PlayerHandle(snap.PlayerKey, snap.DisplayName, snap.CharacterName, null);
                }
            }
        }
        
        if (handle == null) return;

        lock (SyncRoot)
        {
            PlayerDamageSnapshot snapshot = GetOrCreate(handle.Value);
            ApplyHandle(snapshot, handle.Value);
            snapshot.TotalDamage += damage;
            snapshot.CombatDamage += damage;
            snapshot.LastDamage = damage;
            if (damage > snapshot.MaxHitDamage)
                snapshot.MaxHitDamage = damage;
            snapshot.LastUpdatedUtc = DateTime.UtcNow;
            _damageCounter++;
        }

        if (_damageCounter % 10 == 0)
            SaveState();

        Publish();
    }

    private static bool TryAddToActiveCardDamageAggregation(ulong playerKey, decimal damage)
    {
        CardDamageAggregationContext? context = CurrentCardDamageAggregation.Value;
        if (context == null || context.Handle.PlayerKey != playerKey || damage <= 0m)
        {
            return false;
        }

        context.Damage += damage;
        return true;
    }

    private static async Task AwaitAndRestorePoisonContextAsync(Task originalTask, PoisonTrackingContext context)
    {
        try
        {
            await originalTask;
        }
        finally
        {
            if (ReferenceEquals(CurrentPoisonContext.Value, context))
            {
                CurrentPoisonContext.Value = context.Previous;
            }
        }
    }

    public static OverlayState BuildOverlayState()
    {
        List<PlayerDamageSnapshot> snapshots;
        string runToken;
        int combatIndex;
        bool combatActive;
        ulong? activePlayerKey;

        lock (SyncRoot)
        {
            snapshots = Totals.Values
                .OrderByDescending(snapshot => snapshot.TotalDamage)
                .ThenBy(snapshot => snapshot.DisplayName, StringComparer.OrdinalIgnoreCase)
                .Select(snapshot => snapshot.Clone())
                .ToList();
            runToken = _currentRunToken ?? "unknown-run";
            combatIndex = _combatIndex;
            combatActive = _combatActive;
            activePlayerKey = _activePlayerKey;
        }

        return new OverlayState
        {
            RunToken = runToken,
            CombatIndex = combatIndex,
            CombatActive = combatActive,
            ActivePlayerKey = activePlayerKey,
            Players = snapshots
        };
    }

    private static PlayerDamageSnapshot GetOrCreate(PlayerHandle handle)
    {
        if (Totals.TryGetValue(handle.PlayerKey, out PlayerDamageSnapshot? existing))
        {
            return existing;
        }

        PlayerDamageSnapshot created = new()
        {
            PlayerKey = handle.PlayerKey,
            DisplayName = handle.DisplayName,
            CharacterName = string.IsNullOrWhiteSpace(handle.CharacterName) ? "Unknown Character" : handle.CharacterName,
            PortraitTexture = handle.PortraitTexture
        };
        Totals.Add(handle.PlayerKey, created);
        return created;
    }

    private static bool ApplyHandle(PlayerDamageSnapshot snapshot, PlayerHandle handle)
    {
        bool changed = false;

        if (!string.IsNullOrWhiteSpace(handle.DisplayName))
        {
            changed |= !string.Equals(snapshot.DisplayName, handle.DisplayName, StringComparison.Ordinal);
            snapshot.DisplayName = handle.DisplayName;
        }
        if (!string.IsNullOrWhiteSpace(handle.CharacterName))
        {
            changed |= !string.Equals(snapshot.CharacterName, handle.CharacterName, StringComparison.Ordinal);
            snapshot.CharacterName = handle.CharacterName;
        }
        if (handle.PortraitTexture != null)
        {
            changed |= !ReferenceEquals(snapshot.PortraitTexture, handle.PortraitTexture);
            snapshot.PortraitTexture = handle.PortraitTexture;
        }

        return changed;
    }

    private static bool RegisterKnownPlayers(IEnumerable<PlayerHandle> handles)
    {
        bool changed = false;

        foreach (PlayerHandle handle in handles)
        {
            bool existed = Totals.ContainsKey(handle.PlayerKey);
            PlayerDamageSnapshot snapshot = GetOrCreate(handle);
            changed |= !existed;
            changed |= ApplyHandle(snapshot, handle);
        }

        return changed;
    }

    private static List<PlayerHandle> CollectKnownPlayers(params object?[] sources)
    {
        Dictionary<ulong, PlayerHandle> handlesByKey = new();

        foreach (object? source in sources)
        {
            if (source == null)
                continue;

            foreach (PlayerHandle handle in ReflectionHelpers.EnumeratePlayerHandles(source))
            {
                handlesByKey[handle.PlayerKey] = handle;
            }
        }

        return handlesByKey.Values.ToList();
    }

    public static string Format(decimal value)
    {
        return value.ToString("0.##", CultureInfo.InvariantCulture);
    }

    private static void Publish()
    {
        Changed?.Invoke(BuildOverlayState());
    }

    // ── Persistence ────────────────────────────────────────────

    private static void SaveState()
    {
        try
        {
            SavedState state;
            lock (SyncRoot)
            {
                if (string.IsNullOrEmpty(_stableRunId)) return;

                state = new SavedState
                {
                    StableRunId = _stableRunId,
                    CombatIndex = _combatIndex,
                    Players = Totals.Values.Select(s => new SavedPlayer
                    {
                        PlayerKey = s.PlayerKey,
                        DisplayName = s.DisplayName,
                        CharacterName = s.CharacterName,
                        TotalDamage = s.TotalDamage,
                        MaxHitDamage = s.MaxHitDamage
                    }).ToList()
                };
            }

            string json = JsonSerializer.Serialize(state, SavedStateCtx.Default.SavedState);
            System.IO.File.WriteAllText(SavePath, json);
        }
        catch
        {
            // Silently ignore save errors
        }
    }


    private static void DeletePersistedState()
    {
        try
        {
            if (System.IO.File.Exists(SavePath))
            {
                System.IO.File.Delete(SavePath);
            }
        }
        catch
        {
            // Silently ignore cleanup errors
        }
    }

    private static bool TryLoadState(string stableId)
    {
        try
        {
            if (!System.IO.File.Exists(SavePath)) return false;

            string json = System.IO.File.ReadAllText(SavePath);
            SavedState? state = JsonSerializer.Deserialize(json, SavedStateCtx.Default.SavedState);
            if (state == null || !string.Equals(state.StableRunId, stableId, StringComparison.Ordinal))
                return false;

            Totals.Clear();
            _combatIndex = state.CombatIndex;
            _combatActive = false;
            _activePlayerKey = null;

            foreach (SavedPlayer sp in state.Players)
            {
                Totals[sp.PlayerKey] = new PlayerDamageSnapshot
                {
                    PlayerKey = sp.PlayerKey,
                    DisplayName = sp.DisplayName,
                    CharacterName = sp.CharacterName,
                    TotalDamage = sp.TotalDamage,
                    MaxHitDamage = sp.MaxHitDamage
                };
            }

            return true;
        }
        catch
        {
            return false;
        }
    }
}

public sealed class OverlayState
{
    public string RunToken { get; init; } = "unknown-run";

    public int CombatIndex { get; init; }

    public bool CombatActive { get; init; }

    public ulong? ActivePlayerKey { get; init; }

    public IReadOnlyList<PlayerDamageSnapshot> Players { get; init; } = Array.Empty<PlayerDamageSnapshot>();
}

public sealed class PlayerDamageSnapshot
{
    public ulong PlayerKey { get; set; }

    public string DisplayName { get; set; } = "Unknown Player";

    public string CharacterName { get; set; } = "Unknown Character";

    public Texture2D? PortraitTexture { get; set; }

    public bool IsActive { get; set; }

    public decimal TotalDamage { get; set; }

    public decimal CombatDamage { get; set; }

    public decimal LastDamage { get; set; }

    public decimal MaxHitDamage { get; set; }

    public int CardsPlayed { get; set; }

    public int AttackCardsPlayed { get; set; }

    public int SkillCardsPlayed { get; set; }

    public int PowerCardsPlayed { get; set; }

    public int OtherCardsPlayed { get; set; }

    public int AutoCardsPlayed { get; set; }

    public decimal IncomingDamage { get; set; }

    public decimal BlockedDamage { get; set; }

    public decimal HpLostDamage { get; set; }

    public decimal LastDamageReceived { get; set; }

    public decimal MaxDamageReceived { get; set; }

    public decimal BlockGained { get; set; }

    public DateTime LastUpdatedUtc { get; set; }

    public PlayerDamageSnapshot Clone()
    {
        return new PlayerDamageSnapshot
        {
            PlayerKey = PlayerKey,
            DisplayName = DisplayName,
            CharacterName = CharacterName,
            PortraitTexture = PortraitTexture,
            IsActive = IsActive,
            TotalDamage = TotalDamage,
            CombatDamage = CombatDamage,
            LastDamage = LastDamage,
            MaxHitDamage = MaxHitDamage,
            CardsPlayed = CardsPlayed,
            AttackCardsPlayed = AttackCardsPlayed,
            SkillCardsPlayed = SkillCardsPlayed,
            PowerCardsPlayed = PowerCardsPlayed,
            OtherCardsPlayed = OtherCardsPlayed,
            AutoCardsPlayed = AutoCardsPlayed,
            IncomingDamage = IncomingDamage,
            BlockedDamage = BlockedDamage,
            HpLostDamage = HpLostDamage,
            LastDamageReceived = LastDamageReceived,
            MaxDamageReceived = MaxDamageReceived,
            BlockGained = BlockGained,
            LastUpdatedUtc = LastUpdatedUtc
        };
    }
}

public readonly record struct PlayerHandle(ulong PlayerKey, string DisplayName, string? CharacterName, Texture2D? PortraitTexture);

internal sealed class CardDamageAggregationContext
{
    public CardDamageAggregationContext(CardPlay cardPlay, PlayerHandle handle, CardDamageAggregationContext? previous)
    {
        CardPlay = cardPlay;
        Handle = handle;
        Previous = previous;
    }

    public CardPlay CardPlay { get; }

    public PlayerHandle Handle { get; }

    public CardDamageAggregationContext? Previous { get; }

    public decimal Damage { get; set; }
}

internal sealed class PoisonTrackingContext
{
    public PoisonTrackingContext(object target, object applier, PoisonTrackingContext? previous)
    {
        Target = target;
        Applier = applier;
        Previous = previous;
    }

    public object Target { get; }

    public object Applier { get; }

    public PoisonTrackingContext? Previous { get; }
}

internal sealed class PendingDoomDamage
{
    public PendingDoomDamage(object applier, int damage)
    {
        Applier = applier;
        Damage = damage;
    }

    public object Applier { get; }

    public int Damage { get; }
}

// ── Persistence models ─────────────────────────────────────

public sealed class SavedState
{
    public string StableRunId { get; set; } = "";
    public int CombatIndex { get; set; }
    public List<SavedPlayer> Players { get; set; } = new();
}

public sealed class SavedPlayer
{
    public ulong PlayerKey { get; set; }
    public string DisplayName { get; set; } = "";
    public string CharacterName { get; set; } = "";
    public decimal TotalDamage { get; set; }
    public decimal MaxHitDamage { get; set; }
}

[System.Text.Json.Serialization.JsonSerializable(typeof(SavedState))]
internal partial class SavedStateCtx : System.Text.Json.Serialization.JsonSerializerContext { }
