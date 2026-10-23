using System;
using System.Collections.Generic;
using System.Runtime.ExceptionServices;

namespace TE.Plex.Update
{
    public static class ServiceUpdateSequence
    {
        // Keep restoration independent of process-cleanup failures (upstream PR #68).
        public static void Run(Action stop, Action cleanup, Action install, Action restart)
        {
            var failures = new List<Exception>();
            bool stopped = false;
            try
            {
                stop();
                stopped = true;
                cleanup();
                install();
            }
            catch (Exception ex) { failures.Add(ex); }
            finally
            {
                try { if (stopped) cleanup(); }
                catch (Exception ex) { failures.Add(ex); }
                finally
                {
                    try { restart(); }
                    catch (Exception ex) { failures.Add(ex); }
                }
            }
            if (failures.Count == 1) ExceptionDispatchInfo.Capture(failures[0]).Throw();
            if (failures.Count > 1) throw new AggregateException("Plex update/recovery failed.", failures);
        }
    }
}
