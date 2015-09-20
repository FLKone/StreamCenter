//
//  IRCHandler.swift
//  GamingStreamsTVApp
//
//  Created by Olivier Boucher on 2015-09-19.
//  Copyright © 2015 Rivus Media Inc. All rights reserved.
//

import Foundation

protocol IRCHandlerProtocol
{
    var host: String { get }
    var port: Int { get }
    var useSSL: Bool { get }
    var IRCBuffer: [UInt8] { get set }
    
    var commandHandlers: [String : IRCHandlerDelegate] { get set }
    
    var genericCredentials: (String? /* Password */, [String] /* Usernames to attempt */, String /* Computer username */, Bool /* Invisible */, String /* Real name */) { get }
    
    var loop: Bool { get set }
    
    var inputStream: NSInputStream? { get }
    var onputStream: NSOutputStream? { get }
    
    func doLoop()
    func send(command: String , destination: String?, message: String?)
    
    func connect()
    func disconnect()
    func receive(prefix: String?, command: String , destination: String?, message: String?)
}

protocol IRCHandlerDelegate
{
    func respond( target: IRCHandlerBase , prefix: String? , destination: String? , message: String? )
}

class IRCHandlerBase: NSObject, NSStreamDelegate
{
    var host: String
    var port: Int
    var useSSL: Bool
    var genericCredentials: ( String? , [String] , String , Bool , String )?
    
    var IRCBuffer = [UInt8](count: 65536, repeatedValue: 0)
    var commandHandlers = [String : IRCHandlerDelegate]()
    
    var currentNick: Int
    
    var loop: Bool = true
    
    var inputStream: NSInputStream?
    var outputStream: NSOutputStream?
    
    init(host: String, port: Int, useSSL: Bool)
    {
        self.host = host
        self.port = port
        self.useSSL = useSSL
        self.currentNick = 0
        super.init()
    }
    
    deinit
    {
        send("QUIT", destination: nil, message: "Closing connection")
        disconnect()
    }
    
    func send(command: String , destination: String?, message: String?)
    {
        var fullCommand : String = command
        
        if(destination != nil) {
            fullCommand += " "
            fullCommand += destination!
        }
        
        if(message != nil){
            fullCommand += " :"
            fullCommand += message!
        }
        
        fullCommand += "\r\n"
        
        var buffer = [UInt8](fullCommand.utf8)
        outputStream!.write(&buffer, maxLength: fullCommand.utf8.count)
    }
    
    func doLoop()
    {
        if inputStream!.hasBytesAvailable
        {
            var inputStringLines : [String] = []
            while inputStream!.hasBytesAvailable
            {
                let bytesRead = inputStream!.read(&IRCBuffer, maxLength: IRCBuffer.count)
                
                if(bytesRead >= 0){
                    let string = NSString(bytes: &IRCBuffer, length: IRCBuffer.count, encoding: NSUTF8StringEncoding)
                    let lines = string?.componentsSeparatedByString("\r\n")
                    inputStringLines.appendContentsOf(lines!)
                }
                
                IRCBuffer = [UInt8](count: IRCBuffer.count, repeatedValue: 0)
            }
            for string in inputStringLines
            {
                var prefix: String?
                var command: String = ""
                var destination : String?
                var message : String?
                
                let msgPattern = "([a-z0-9.@!_]+)?\\s([a-zA-Z0-9]+)?\\s(\\#*[a-z0-9]+)\\s:?(.+)?"
                
                var regex : NSRegularExpression?
                do {
                    //First we check for any type of command except anormal ones like PING
                    regex = try NSRegularExpression(pattern: msgPattern, options: .AllowCommentsAndWhitespace)
                    let matches = regex?.matchesInString(string, options: NSMatchingOptions.WithTransparentBounds, range: NSRange(location: 0, length: string.utf8.count))
                    if(matches != nil && matches?.count > 0){
                        let match = matches!.first!
                        if(match.numberOfRanges == 5){
                            let region = (string as NSString)
                            
                            prefix = region.substringWithRange(match.rangeAtIndex(1))
                            command = region.substringWithRange(match.rangeAtIndex(2))
                            destination = region.substringWithRange(match.rangeAtIndex(3))
                            message = region.substringWithRange(match.rangeAtIndex(4))
                        }
                        
                        receive(prefix, command: command , destination: destination, message: message)
                    }
                    else {
                        //Check if it is a ping request
                        if(string.hasPrefix("PING")) {
                            var msg : String? = nil
                            if let indexSemi = string.rangeOfString(":") {
                                msg = string.substringFromIndex(indexSemi.startIndex)
                            }
                            receive(nil, command: "PING", destination: nil, message: msg)
                        }
                    }
                    
                    
                } catch let error as NSError {
                    NSLog(error.localizedDescription)
                }
            }
            
        }
    }
    
    func connect()
    {
        NSStream.getStreamsToHostWithName(host, port: port,
            inputStream: &inputStream, outputStream: &outputStream)
        
        inputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        
        inputStream!.delegate = self
        outputStream!.delegate = self
        
        inputStream!.open()
        outputStream!.open()
        
        if useSSL
        {
            inputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        }
        loop = true
    }
    
    func disconnect()
    {
        loop = false
        
        inputStream!.close()
        outputStream!.close()
        
        inputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        
        inputStream = nil
        outputStream = nil
    }
    
    func receive( prefix: String?, command: String , destination: String?, message: String?)
    {
        let handler = commandHandlers[command]
        if handler != nil
        {
            handler!.respond(self, prefix: prefix, destination: destination , message: message)
        }

    }
}
