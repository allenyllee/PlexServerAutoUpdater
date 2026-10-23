using System;
using System.Text.RegularExpressions;

namespace TE.Plex.Update
{
    public static class InstallerArguments
    {
        public static string Create(bool is64Bit, string configured, string logFile)
        {
            if (string.IsNullOrWhiteSpace(logFile) || logFile.Contains("\""))
                throw new ArgumentException("Invalid installer log path.", nameof(logFile));
            if (!is64Bit)
                return (configured ?? "/install /quiet /norestart /log").Trim() + " \"" + logFile + "\"";

            string parameters = string.IsNullOrWhiteSpace(configured) ? "/verysilent /norestart" : configured.Trim();
            parameters = Regex.Replace(parameters, @"(?i)(?:^|\s)/log=?(?=\s|$)", "").Trim();
            // Inno Setup requires /LOG=path and explicit suppression of migration message boxes.
            return parameters + " /SUPPRESSMSGBOXES /SP- /LOG=\"" + logFile + "\"";
        }
    }
}
