using System;
using SJARC;

class TargetSelectionTests {
    static int checks;
    static void Check(bool value,string message) { checks++; if(!value) throw new Exception(message); }
    static void Main() {
        var rf9=new Install {Path=@"C:\RF9\RealFlight.exe",Label="RealFlight 9 / 9.5 / 9.5S (9.50.065.0)",Edition="9 / 9.5 / 9.5S"};
        var evo=new Install {Path=@"D:\Steam\RealFlight Evolution\RealFlight64.exe",Label="RealFlight Evolution (10.10.215)",Edition="Evolution"};
        string[] both={@"C:\Users\Test\Documents\RealFlight 9",@"C:\Users\Test\Documents\RealFlight Evolution"};
        Check(TargetSelection.InitialInstall(2)==-1,"Multiple installations must be unselected");
        Check(TargetSelection.InitialInstall(0)==-1,"No installation cannot be selected");
        Check(TargetSelection.InitialInstall(1)==0,"One installation may be selected");
        Check(rf9.ToString().Contains(rf9.Path)&&evo.ToString().Contains(evo.Path),"Both labels must expose exact executable path");
        var first=TargetSelection.Candidates(rf9.Edition,both);
        var second=TargetSelection.Candidates(evo.Edition,both);
        Check(first.Count==1&&first[0]==both[0],"RF9 must show only RF9 folder");
        Check(second.Count==1&&second[0]==both[1],"Switching to Evolution must show only Evolution folder");
        Check(TargetSelection.InitialRoot(first.Count,both.Length)==-1,"Multiple folders require explicit selection, even if filtered");
        Check(TargetSelection.InitialRoot(1,1)==0,"Single matching folder may be suggested");
        Check(TargetSelection.InitialRoot(0,1)==-1,"An unrelated sole folder must not be suggested");
        Check(TargetSelection.Candidates(evo.Edition,new[]{both[0]}).Count==0,"No fallback to RF9 when Evolution data folder missing");
        Check(TargetSelection.Candidates("",both).Count==0,"Unknown executable must not default to RF9");
        Check(TargetSelection.KnownMismatch(evo.Edition,both[0]),"Evolution/RF9 mismatch");
        Check(TargetSelection.KnownMismatch(rf9.Edition,both[1]),"RF9/Evolution mismatch");
        Check(!TargetSelection.KnownMismatch(rf9.Edition,both[0]),"RF9 matching target");
        Check(!TargetSelection.KnownMismatch(evo.Edition,both[1]),"Evolution matching target");
        Check(TargetSelection.Candidates(rf9.Edition,new[]{@"C:\Docs\RealFlight 9.5",@"C:\Docs\RealFlight 9.5S"}).Count==2,"RF9 aliases must remain selectable");
        Check(TargetSelection.InitialRoot(2,2)==-1,"Ambiguous RF9 roots must not be guessed");
        Check(TargetSelection.Candidates(evo.Edition,new[]{both[1],both[1].ToUpperInvariant()}).Count==1,"Ignore duplicate folder spelling");
        Check(TargetSelection.RootEdition(both[1]+@"\")=="Evolution","Trailing separator");
        Console.WriteLine("Target selection checks passed: "+checks);
    }
}
