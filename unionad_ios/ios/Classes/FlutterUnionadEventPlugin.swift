//
//  FlutterUnionadEventPlugin.swift
//  flutter_unionad
//
//  Created by gstory0404@gmail on 2020/9/3.
//

import Foundation
import Flutter

public class FlutterUnionadEnentPlugin : NSObject, FlutterStreamHandler{
    
    private final class WeakPluginRef {
        weak var value: FlutterUnionadEnentPlugin?
        init(_ value: FlutterUnionadEnentPlugin) { self.value = value }
    }
    
    private static var instances: [WeakPluginRef] = []
    private static var pendingEvents: [NSDictionary] = []
    
    private var eventSink: FlutterEventSink? = nil
    private var eventChannel: FlutterEventChannel? = nil
    
    init(_ registrar: FlutterPluginRegistrar){
        super.init()
        let channel = FlutterEventChannel.init(name: FlutterUnionadConfig.event.adevent, binaryMessenger:registrar.messenger())
        channel.setStreamHandler((self as FlutterStreamHandler & NSObjectProtocol))
        self.eventChannel = channel
        let registerInstance = {
            Self.instances.removeAll { $0.value == nil }
            Self.instances.append(WeakPluginRef(self))
        }
        if Thread.isMainThread {
            registerInstance()
        } else {
            DispatchQueue.main.async(execute: registerInstance)
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        if !Self.pendingEvents.isEmpty {
            let replay = Self.pendingEvents
            Self.pendingEvents.removeAll()
            replay.forEach { events($0) }
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    //发送event：向所有当前处于监听状态的 Flutter 引擎投递，避免后台引擎（如 HomeWidgetBackgroundWorker）后注册覆盖主引擎通道
    public func sendEvent(event:NSDictionary) {
        DispatchQueue.main.async {
            Self.instances.removeAll { $0.value == nil }
            let sinks = Self.instances.compactMap { $0.value?.eventSink }
            if !sinks.isEmpty {
                sinks.forEach { $0(event) }
            } else {
                // 监听尚未建立时先缓存，避免 onReady 等关键事件丢失导致上层超时。
                Self.pendingEvents.append(event)
                if Self.pendingEvents.count > 50 {
                    Self.pendingEvents.removeFirst(Self.pendingEvents.count - 50)
                }
            }
        }
    }

}
