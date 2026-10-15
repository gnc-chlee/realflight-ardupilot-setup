using System.Reflection;

// Stand-in for MissionPlanner.exe in the installer tests: only its file version is read (compile with /define:V183 for 1.3.83).
#if V183
[assembly: AssemblyFileVersion("1.3.83.0")]
#else
[assembly: AssemblyFileVersion("1.3.82.0")]
#endif

static class FakePlanner {
    static void Main() { }
}
