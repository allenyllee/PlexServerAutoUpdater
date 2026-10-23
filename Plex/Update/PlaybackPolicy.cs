using System;

namespace TE.Plex.Update
{
    public static class PlaybackPolicy
    {
        public static bool CanUpdate(int playback, int recordings, bool force)
        {
            if (playback < 0 || recordings < 0)
                throw new InvalidOperationException("Playback or recording status is unknown; refusing to interrupt Plex.");
            return recordings == 0 && (playback == 0 || force);
        }
    }
}
