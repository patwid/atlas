# 0030. The membership sweep: access that is taken away reaches the device

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (fixes a privacy defect found while building sharing; the owner agreed to do it before the coach's view)

## Context

Incremental pulls ([0016](0016-sync-core-outbox-and-cursor.md)) return records that *changed*. A record the user can no longer read has not
changed, and a removed share or coach grant is not visible to the person it removed ([0009](0009-data-model-and-api-rules.md)). So when an owner
stopped sharing a plan, or an athlete removed a coach, the server hid the data at once but **the other person's device kept it** until a full
resync (a new device, or 80 days without syncing). A test against a real server showed it ([0029](0029-sharing-plans.md), known gap). For coach
access this meant a coach kept the athlete's activities on his device after being removed.

## Decision

- **A membership sweep**: now and then, after the ordinary pull of a collection, the client lists the IDs of the records the user can read *now*
  (`fields=id`, in ID order) and removes the collection's local records that are not among them. Records with unsent local edits are kept.
  It uses the existing `Reconcile` step that full resyncs already use.
- **Paging by "after the last ID seen"** (`filter=id > "..."`, 500 per request, until a page is short), not by page number. A walk by page number
  can skip a record when others are added or removed meanwhile, and a skipped record would be deleted from the device although the user can
  still read it. This is pinned against the real server by a contract test.
- **Held until confirmed.** The removals are only emitted after the session check at the end of the run, like cursors and full-resync reconciles
  ([0018](0018-sync-engine.md)). A token that stops being valid mid-run makes PocketBase answer as an anonymous user with *empty lists and status
  200* ([0017](0017-session-and-http-layer.md)); taken at face value a sweep would conclude that everything is gone. A test makes the token fail
  after the start check and checks that nothing is removed and the sweep is not recorded.
- **How often**: at most every 10 minutes (`sweep_interval_seconds`), and only when a sweep actually ran. The time of the last confirmed sweep is
  kept on the device (`swept_at`). Collections that are fully resynced in the same run are not swept as well: a full resync is authoritative by itself.
  A new device therefore sweeps from its second run on.
- **Cost**: one small request per collection and 500 records, so about seven requests per ten minutes of use for a typical user. Only IDs travel.
- **Failure handling**: a failed or refused listing never removes anything. A server error retries later; an expired session asks to sign in; a
  refused listing (a rule problem) skips that collection and carries on.

## Consequences

- Access removal now reaches the other person's device within about ten minutes of their next sync, instead of never. It still cannot take back
  what they have already seen or copied, and a device that stays offline keeps its data until it syncs; the privacy notice must say both.
- A record removed from the device by a sweep is gone locally until it changes on the server again; because the sweep lists *readable* IDs, that
  only happens to records the user truly cannot read.
- Tombstones that the server has purged ([0014](0014-purge-soft-deleted-rows.md)) are removed from devices by the same mechanism.
- A user with thousands of records pays more requests per sweep (one per 500). The interval can be widened if that ever matters.
- The whole-app tests show both cases on real data: a plan whose share was removed disappears from the recipient's screen and device database, and
  an athlete's activities disappear from the removed coach's device while his own stay. With the sweep switched off, the first of them fails.

## A lesson about the tests

Adding the sweep made the whole-app tests fail intermittently, in different tests each time (one run in three to eight): records that were certainly
on the server were missing from a device. The cause was in the test harness, not the app. The tests simulate several users with one shared fake
IndexedDB, and `window.close()` in jsdom stops timers but not requests already under way. A closed window's last sync run could still finish and its
sweep would remove records of the *next* test's user from the shared database. A real closed tab cannot do that, and a real device holds one user's
data. The harness now behaves like a real tab: after `close()`, nothing the app is waiting for ever arrives. Twelve consecutive runs of the whole
browser-side suite (33 tests each) then passed. Failure messages from these tests now include the text on screen at the time, which made the
pattern visible. The point worth keeping: a feature that *deletes* local data turns any cross-talk between simulated devices from harmless into flaky.
