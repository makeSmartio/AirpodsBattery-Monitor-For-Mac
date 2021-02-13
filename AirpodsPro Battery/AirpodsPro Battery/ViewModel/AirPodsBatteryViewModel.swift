//
//  BatteryViewModel.swift
//  AirpodsPro Battery
//
//  Created by Mohamed Arradi on 13/12/2019.
//  Copyright © 2019 Mohamed Arradi. All rights reserved.
//

import Foundation
import IOBluetooth
import WidgetKit

class AirPodsBatteryViewModel: BluetoothAirpodsBatteryManagementProtocol {
    
    var leftBatteryValue: String = "--"
    var rightBatteryValue: String = "--"
    var caseBatteryValue: String = "--"
    var leftBatteryProgressValue: CGFloat = 0.0
    var rightBatteryProgressValue: CGFloat = 0.0
    var caseBatteryProgressValue: CGFloat = 0.0
    var displayStatusMessage: String = ""
    
    var deviceName: String {
        get {
            return preferenceManager.getValuePreferences(from: PreferenceKey.deviceName.rawValue) as? String ?? ""
        }
    }
    
    var deviceAddress: String {
        get {
            return preferenceManager.getValuePreferences(from: PreferenceKey.deviceAddress.rawValue) as? String ?? ""
        }
    }
    
    var connectionStatus: AirpodsConnectionStatus = .disconnected
    private (set) var scriptHandler: ScriptsHandler?
    private (set) var preferenceManager: PrefsPersistanceManager!
    
    init(scriptHandler: ScriptsHandler = ScriptsHandler(scriptsName: ["battery-airpods.sh", "mapmac.txt", "apple-devices-verification.sh"]),
         preferenceManager: PrefsPersistanceManager = PrefsPersistanceManager()) {
        self.scriptHandler = scriptHandler
        self.preferenceManager = preferenceManager
    }
    
    func updateBatteryInformation(completion: @escaping (_ success: Bool, _ status: AirpodsConnectionStatus) -> Void) {
        
        guard let scriptHandler = scriptHandler else {
            completion(false, .disconnected)
            return
        }
        
        let script = scriptHandler.scriptDiskFilePath(scriptName: "battery-airpods.sh")
        let macMappingFile = scriptHandler.scriptDiskFilePath(scriptName: "mapmac.txt")
        
        scriptHandler.execute(commandName: "sh", arguments: ["\(script)","\(macMappingFile)"]) { [weak self] (result) in
            
            switch result {
            case .success(let value):
                let pattern = "\\d+"
                let groups = value.groups(for: pattern).flatMap({$0})
                DispatchQueue.main.async {
                self?.processBatteryEntries(groups: groups)
                self?.processAirpodsDetails()
                }
               
                completion(true, self?.connectionStatus ?? .disconnected)
            case .failure( _):
                completion(false, self?.connectionStatus ?? .disconnected)
            }
        }
    }
    
    fileprivate func updateAirpodsNameAndAddress(name: String, address: String) {
        
        if !address.isEmpty && address.count > 4 {
            preferenceManager.savePreferences(key: PreferenceKey.deviceName.rawValue, value: "\n \(name) \r\n -\(address)-")
        } else {
            preferenceManager.savePreferences(key: PreferenceKey.deviceName.rawValue, value: name)
        }
        
        preferenceManager.savePreferences(key: PreferenceKey.deviceAddress.rawValue, value: address)
        NotificationCenter.default.post(name: NSNotification.Name("update_device_name"), object: nil)
    }
    
    func processBatteryEntries(groups: [String]) {
        
        self.displayStatusMessage = ""
        
        if groups.count > 0 {
            self.connectionStatus = .connected
            
            if let caseValue = Int(groups[0]) {
                let value = caseValue > 0 ? "\(caseValue) %": "nc"
                self.caseBatteryValue = value
                self.caseBatteryProgressValue = CGFloat(caseValue)
            }
            
            if let leftValue = Int(groups[1]) {
                self.leftBatteryValue = "\(leftValue) %"
                self.leftBatteryProgressValue = CGFloat(leftValue)
                self.displayStatusMessage.append("Left: \(leftValue)% - ")
            }
            
            if let rightValue = Int(groups[2]) {
                self.rightBatteryValue = "\(rightValue) %"
                self.rightBatteryProgressValue = CGFloat(rightValue)
                self.displayStatusMessage.append("Right: \(rightValue)%")
            }
        } else {
            self.connectionStatus = .disconnected
            self.leftBatteryValue = "--"
            self.leftBatteryProgressValue = CGFloat(0)
            self.rightBatteryValue = "--"
            self.rightBatteryProgressValue = CGFloat(0)
            self.caseBatteryValue = "--"
            self.caseBatteryProgressValue = CGFloat(0)
            self.displayStatusMessage = ""
        }
        
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "com.mac.AirpodsPro-Battery.batteryWidget")
        }
    }
    
    func processBatteryLevelUserDefaults(left: Int? = nil, right: Int? = nil, case: Int? = nil) {
        if let left = left {
            preferenceManager.savePreferences(key: PreferenceKey.BatteryValue.left.rawValue, value: left)
        }
    }
    func processAirpodsDetails() {
        self.fetchAirpodsName { (deviceName, deviceAddress) in
            self.isAppleDevice(deviceAddress: deviceAddress) { [weak self] (success) in
                guard !deviceName.isEmpty, !deviceAddress.isEmpty else {
                    return
                }
                self?.updateAirpodsNameAndAddress(name: deviceName, address: deviceAddress)
            }
        }
    }
    
    func fetchAirpodsName(completion: @escaping (_ deviceName: String, _ deviceAddress: String) -> Void) {
        
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            completion("", "")
            return
        }
        
        if let device = findLatestDevices(connected: true, devices: devices) {
            completion(device.nameOrAddress, device.addressString)
        } else if let device = findLatestDevices(connected: false, devices: devices) {
             completion(device.nameOrAddress, device.addressString)
        } else {
             completion("", "")
        }
    }
    
    fileprivate func findLatestDevices(connected: Bool, devices: [IOBluetoothDevice]) -> IOBluetoothDevice? {
        
        guard let device = devices.first(where: { $0.isConnected() == connected
              && $0.deviceClassMajor == kBluetoothDeviceClassMajorAudio
              && $0.deviceClassMinor == kBluetoothDeviceClassMinorAudioHeadphones }) else {
                return nil
        }
        return device
    }
    
    func isAppleDevice(deviceAddress: String, completion: @escaping (Bool) -> Void) {
        
        let script = scriptHandler?.scriptDiskFilePath(scriptName: "apple-devices-verification.sh") ?? ""
        let macMappingFile = scriptHandler?.scriptDiskFilePath(scriptName: "mapmac.txt") ?? ""
        
        scriptHandler?.execute(commandName: "sh", arguments: ["\(script)", "\(deviceAddress)","\(macMappingFile)"]) { (result) in
            
            switch result {
            case .success(let value):
                value.trimmingCharacters(in: .whitespacesAndNewlines) == "0" ? completion(false) : completion(true)
            case .failure( _):
                completion(false)
            }
            
            completion(true)
        }
    }
    
    func toogleCurrentBluetoothDevice() {
        
        guard !deviceAddress.isEmpty, let bluetoothDevice = IOBluetoothDevice(addressString: deviceAddress) else {
            print("Device not found")
            return
        }
        
        if !bluetoothDevice.isPaired() {
            print("Device not paired")
            return
        }
        
        if bluetoothDevice.isConnected() {
            bluetoothDevice.closeConnection()
        } else {
            bluetoothDevice.openConnection()
        }
    }
}

