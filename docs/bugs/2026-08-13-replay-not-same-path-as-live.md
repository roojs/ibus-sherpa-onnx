# Replay does not match live

**Status:** ⏳ `.feedlog` checksums added — need new listen + Replay  
**Reported:** 2026-08-13  
**Evidence:** `200603` (20:06) — playing back the saved session twice gave the same text both times, but that text was not the same as live (~72%).

## What we want

Save the listen. Play it back. Get the **same words** as live.

## What we know

- The saved audio file sizes line up with the saved chunk list.
- Playing that save back is **stable** (same result every time).
- That result is still **not** what live wrote.

So either live did not send the recognizer the same audio we saved, or live and replay still differ somehow after that.

## `.feedlog`

While recording, Capture appends a checksum line for each reset / push / flush
(`GLib.debug #feed …`, and the ''.feedlog'' sidecar). No separate FeedLog type.

## Next

1. Reinstall engine + setup.  
2. New listen → confirm `.feedlog` exists.  
3. Replay → read `feedlog OK` / `FAIL`.  
4. User ✅ only when Replay text matches live `.txt`.
