using System;
using System.Collections.Generic;
using System.IO;

namespace SJARC {
    // Pure selection rules, shared by the form and the headless regression tests.
    sealed class Install {
        public string Path, Label, Edition;
        public override string ToString() { return Label + "  —  " + Path; }
    }
    static class TargetSelection {
        public static int InitialInstall(int count) { return count == 1 ? 0 : -1; }
        public static string RootEdition(string path) {
            string leaf;
            try { leaf = System.IO.Path.GetFileName(path.Trim().Trim('"').TrimEnd('\\','/')); }
            catch (ArgumentException) { return ""; }
            if (String.Equals(leaf,"RealFlight Evolution",StringComparison.OrdinalIgnoreCase)) return "Evolution";
            if (String.Equals(leaf,"RealFlight 8",StringComparison.OrdinalIgnoreCase)) return "8";
            foreach (string name in new[]{"RealFlight 9","RealFlight 9.5","RealFlight 9.5S"})
                if (String.Equals(leaf,name,StringComparison.OrdinalIgnoreCase)) return "9 / 9.5 / 9.5S";
            return "";
        }
        public static List<string> Candidates(string edition, IEnumerable<string> roots) {
            var result = new List<string>();
            if (String.IsNullOrEmpty(edition)) return result;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string root in roots)
                if (RootEdition(root)==edition && seen.Add(root)) result.Add(root);
            return result;
        }
        public static int InitialRoot(int candidates, int allRoots) {
            // Multiple data folders always require an explicit choice, even after filtering.
            return candidates == 1 && allRoots == 1 ? 0 : -1;
        }
        public static bool KnownMismatch(string edition, string root) {
            string actual = RootEdition(root);
            return actual!="" && actual!=edition;
        }
    }
}
