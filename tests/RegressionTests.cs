using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using TE.Plex;
using TE.Plex.Update;

internal static class RegressionTests
{
    private sealed class FakeHttp : HttpMessageHandler
    {
        public int Requests;
        public Func<HttpRequestMessage,HttpResponseMessage> Response;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        { Requests++; return Task.FromResult(Response(request)); }
    }
    private static Api FakeApi(FakeHttp handler)
    {
        var api = new Api("127.0.0.1","test-token");
        typeof(Api).GetField("_client",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(api,new HttpClient(handler));
        return api;
    }
    private static HttpResponseMessage Xml(string xml)
    { return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent(xml)}; }
    private static int count;
    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL: " + name);
        count++;
        Console.WriteLine("PASS: " + name);
    }
    private static void Throws(Action action, string name)
    {
        try { action(); }
        catch { Check(true, name); return; }
        throw new Exception("FAIL: expected exception: " + name);
    }
    private static string Binary(string directory, ushort machine)
    {
        string path = Path.Combine(directory, Guid.NewGuid() + ".exe");
        using (var writer = new BinaryWriter(File.Create(path)))
        {
            writer.Write(new byte[128]);
            writer.BaseStream.Position = 0;
            writer.Write((ushort)0x5a4d);
            writer.BaseStream.Position = 0x3c;
            writer.Write(64);
            writer.BaseStream.Position = 64;
            writer.Write(0x00004550u);
            writer.Write(machine);
        }
        return path;
    }
    private static int Main()
    {
        string temporary = Path.Combine(Path.GetTempPath(), "plex-updater-tests-" + Guid.NewGuid());
        Directory.CreateDirectory(temporary);
        try
        {
            Check(BinaryArchitecture.Is64Bit(Binary(temporary,0x8664)), "x64 PE in a custom directory");
            Check(!BinaryArchitecture.Is64Bit(Binary(temporary,0x014c)), "x86 PE is not misidentified as updater architecture");
            Throws(() => BinaryArchitecture.Is64Bit(Binary(temporary,0xaa64)), "unsupported architecture fails closed");
            string broken = Path.Combine(temporary,"truncated.exe");
            File.WriteAllBytes(broken,new byte[4]);
            Throws(() => BinaryArchitecture.Is64Bit(broken), "truncated executable rejected");
            string badOffset = Binary(temporary,0x8664);
            using (var writer = new BinaryWriter(File.OpenWrite(badOffset)))
            { writer.BaseStream.Position=0x3c; writer.Write(int.MaxValue); }
            Throws(() => BinaryArchitecture.Is64Bit(badOffset), "out-of-range PE offset rejected");

            var metadata = new SystemType { Version="1.43.5.11029-latest", Releases=new List<Release> {
                new Release {Build="windows-x86",Url="https://downloads.plex.tv/PlexMediaServer-1.42.2.10156-old-x86.exe",CheckSum="32"},
                new Release {Build="windows-x86_64",Url="https://downloads.plex.tv/PlexMediaServer-1.43.5.11029-new-x86_64.exe",CheckSum="64"}
            }};
            Check(metadata.GetVersionString(false)=="1.42.2.10156-old", "x86 package version overrides platform x64 version (issue 67)");
            Check(metadata.GetVersionString(true)=="1.43.5.11029-new", "x64 release version selected");
            Check(metadata.GetCheckSum(true)=="64", "checksum follows the same architecture");
            var package = new Package(temporary,UpdateChannel.Public,"",false);
            typeof(Package).GetProperty("LatestWindowsVersion").GetSetMethod(true).Invoke(package,new object[]{metadata});
            Check(package.GetVersion()==new Version("1.42.2.10156"), "Package.GetVersion uses selected release");
            string folder = (string)typeof(Package).GetMethod("GetPath",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(package,null);
            Check(folder.Contains("1.42.2.10156-old"), "cache folder matches actual package version");
            metadata.Releases[1].Url=metadata.Releases[0].Url;
            Throws(() => metadata.GetVersionString(true), "architecture and filename mismatch rejected");

            var events = new List<string>();
            ServiceUpdateSequence.Run(() => events.Add("stop"),()=>events.Add("cleanup"),()=>events.Add("install"),()=>events.Add("start"));
            Check(string.Join(",",events)=="stop,cleanup,install,cleanup,start", "successful update keeps complete lifecycle");
            events.Clear();
            Throws(() => ServiceUpdateSequence.Run(()=>events.Add("stop"),()=>{events.Add("cleanup");throw new Exception("access denied");},()=>events.Add("install"),()=>events.Add("start")), "cleanup failure reported");
            Check(events.Contains("start")&&!events.Contains("install"), "cleanup access denied still restarts without installing (PR 68)");
            events.Clear();
            Throws(() => ServiceUpdateSequence.Run(()=>{events.Add("stop");throw new Exception("stop pending timeout");},()=>events.Add("cleanup"),()=>events.Add("install"),()=>events.Add("start")), "stop timeout reported");
            Check(string.Join(",",events)=="stop,start", "partial stop failure still attempts recovery");
            events.Clear();
            Throws(() => ServiceUpdateSequence.Run(()=>events.Add("stop"),()=>events.Add("cleanup"),()=>{events.Add("install");throw new Exception("installer 1603");},()=>events.Add("start")), "installer failure reported");
            Check(events[events.Count-1]=="start", "installer failure restores service");
            Throws(() => ServiceUpdateSequence.Run(()=>{},()=>{},()=>{},()=>{throw new Exception("restart failed");}), "restart failure cannot be reported as success");
            Check(PlaybackPolicy.CanUpdate(0,0,false), "idle server can update");
            Check(!PlaybackPolicy.CanUpdate(1,0,false), "active playback waits");
            Check(PlaybackPolicy.CanUpdate(1,0,true), "force preserves original playback override");
            Check(!PlaybackPolicy.CanUpdate(0,1,true), "force never interrupts a recording");
            Throws(()=>PlaybackPolicy.CanUpdate(-1,0,true), "unknown playback cannot be forced");
            Throws(()=>PlaybackPolicy.CanUpdate(0,-1,false), "unknown recordings block update");
            var noDvr = new FakeHttp{Response=request=>Xml("<MediaContainer size='0' />")};
            Check(FakeApi(noDvr).GetInProgressRecordingCount()==0 && noDvr.Requests==1, "no DVR avoids unauthorized recordings endpoint");
            var recording = new FakeHttp{Response=request=>request.RequestUri.AbsolutePath=="/livetv/dvrs" ? Xml("<MediaContainer size='1' />") : Xml("<MediaContainer><MediaGrabOperation status='inprogress'/><MediaGrabOperation status='scheduled'/></MediaContainer>")};
            Check(FakeApi(recording).GetInProgressRecordingCount()==1, "only in-progress DVR recordings counted");
            var unauthorized = new FakeHttp{Response=request=>new HttpResponseMessage(HttpStatusCode.Unauthorized)};
            Check(FakeApi(unauthorized).GetInProgressRecordingCount()==Api.Unknown, "DVR authentication failure remains unknown");
            var malformed = new FakeHttp{Response=request=>Xml("not XML")};
            Check(FakeApi(malformed).GetInProgressRecordingCount()==Api.Unknown, "malformed DVR response fails closed");
            var missingDvrSize = new FakeHttp{Response=request=>Xml("<MediaContainer />")};
            Check(FakeApi(missingDvrSize).GetInProgressRecordingCount()==Api.Unknown, "missing DVR count remains unknown");
            string logDirectory = Path.Combine(temporary,"logs");
            TE.Log.SetFolder(logDirectory);
            Check(TE.Log.Folder==logDirectory, "log parameter retains requested directory");
            Console.WriteLine("All " + count + " regression assertions passed.");
            return 0;
        }
        catch(Exception ex) { Console.Error.WriteLine(ex); return 1; }
        finally { Directory.Delete(temporary,true); }
    }
}
