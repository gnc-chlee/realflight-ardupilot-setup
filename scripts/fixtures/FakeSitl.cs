using System;
using System.IO;
using System.Threading;

// Stand-in for Mission Planner's ArduPlane.exe in the installer tests: records how it was started, then idles until killed.
static class FakeSitl {
    static void Main() {
        File.WriteAllText("fake-sitl.txt", Environment.CommandLine + "\n" + Directory.GetCurrentDirectory() + "\n");
        Thread.Sleep(Timeout.Infinite);
    }
}
