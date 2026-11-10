using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Windows.Devices.Enumeration;
public static class SasBluetoothPairing {
 public static async Task<string> Run(string exactName) {
  var watcher=DeviceInformation.CreateWatcher("",new string[]{"System.Devices.Aep.ProtocolId"},DeviceInformationKind.AssociationEndpoint);
  DeviceInformation target=null;
  object gate=new object();
  var seen=new Dictionary<string,DeviceInformation>(); watcher.Added += (sender,device) => { lock(gate) { seen[device.Id]=device;  if(device.Name == exactName) target=device; } }; watcher.Updated += (sender,update) => { lock(gate) { DeviceInformation device; if(seen.TryGetValue(update.Id,out device)) { device.Update(update); if(device.Name == exactName) target=device; } } };
  watcher.Start();
  try {
   for(int i=0;i<80;i++) {
    DeviceInformation found; lock(gate) { found=target; }
    if(found!=null) {
     Console.WriteLine("TARGET_FOUND="+found.Name);
     if(found.Pairing.IsPaired) return "ALREADY_PAIRED";
     if(!found.Pairing.CanPair) return "TARGET_NOT_PAIRABLE";
     var custom=found.Pairing.Custom; custom.PairingRequested += (s,a) => { if(a.PairingKind == DevicePairingKinds.ConfirmOnly) a.Accept(); }; var pair=custom.PairAsync(DevicePairingKinds.ConfirmOnly).AsTask();
     if(await Task.WhenAny(pair,Task.Delay(30000))!=pair) return "PAIRING_TIMEOUT_REQUIRES_INSPECTION";
     return "PAIRING_RESULT="+(await pair).Status;
    }
    await Task.Delay(250);
   }
   return "TARGET_NOT_DISCOVERED";
  } finally { watcher.Stop(); }
 }
}
