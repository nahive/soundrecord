//
//  ViewController.swift
//  soundrecord
//
//  Created by Szymon Maślanka on 23/02/16.
//  Copyright © 2016 Szymon Maślanka. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
  
  // holds the state of recording/view
  private enum RecordingState {
    case Ready, Recording(seconds: Double), Uploading(percent: Int), Error(error: String)
    
    var description: String {
      switch self {
      case .Ready: return "Ready"
      case .Recording(let seconds): return "Recording: \(seconds)"
      case .Uploading(let percent): return "Uploading: \(percent) %"
      case .Error(let error): return "Error: \(error)"
      }
    }
  }
  
  private let button = UIButton()
  private let label = UILabel()
  
  // current state of recording
  private var currentState = RecordingState.Ready {
    didSet {
      label.text = currentState.description
      
      switch currentState {
      case .Ready: button.enabled = true
      case .Recording: button.enabled = false
      case .Uploading: button.enabled = false
      case .Error: button.enabled = true
      }
    }
  }
  
  private var recorder: AVAudioRecorder?
  
  // url for saving recorded file
  private var soundURL: NSURL? {
    let fileManager = NSFileManager.defaultManager()
    let urls = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
    let documentDirectory = urls[0] as NSURL
    let soundURL = documentDirectory.URLByAppendingPathComponent("sound.m4a")
    return soundURL
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    initRecorder()
    initLabel()
    initButton()
    
    currentState = .Ready
  }
  
  // initializes recorder with settings
  private func initRecorder(){
    guard let soundURL = soundURL else {
        return
    }
    
    func setupRecorder(){
      let soundSettings = [AVSampleRateKey : NSNumber(float: Float(44100.0)),
                            AVFormatIDKey : NSNumber(int: Int32(kAudioFormatMPEG4AAC)),
                            AVNumberOfChannelsKey : NSNumber(int: 1),
                            AVEncoderAudioQualityKey : NSNumber(int: Int32(AVAudioQuality.Medium.rawValue))]
      
      do {
        recorder = try AVAudioRecorder(URL: soundURL, settings: soundSettings)
        recorder?.delegate = self
        recorder?.meteringEnabled = true
        recorder?.prepareToRecord()
      } catch {
        print("failed to setup recorder")
      }
    }
    
    do {
      try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryRecord)
      try AVAudioSession.sharedInstance().setActive(true)
      
      AVAudioSession.sharedInstance().requestRecordPermission({ (allowed) in
        if allowed {
          setupRecorder()
        } else {
          print("failed to aquire permission to record")
          return
        }
      })
    } catch {
      print("failed to init recorder")
      return
    }
  }
  
  // initializes state label
  private func initLabel(){
    label.frame = CGRect(x: view.bounds.width/2 - 100, y: view.bounds.height/2 - 66, width: 200, height: 44)
    label.textAlignment = .Center
    
    view.addSubview(label)
  }
  
  // initializes record button
  private func initButton(){
    button.frame = CGRect(x: view.bounds.width/2 - 100, y: view.bounds.height/2 - 22, width: 200, height: 44)
    button.setTitle("Start recording", forState: .Normal)
    button.setTitleColor(UIColor.blueColor(), forState: .Normal)
    button.setTitleColor(UIColor.lightGrayColor(), forState: .Disabled)
    
    button.addTarget(self, action: Selector("startRecording"), forControlEvents: .TouchUpInside)
    
    view.addSubview(button)
  }
  
  // private vars for displaying record time
  private var recordingTime = 0.0
  private var recordingTimer: NSTimer?
  
  // starts recording and fires timer
  func startRecording(){
    currentState = .Recording(seconds: 0)
    
    recorder?.record()
    
    performSelector(Selector("stopRecording"), withObject: nil, afterDelay: 10.0)
    recordingTimer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: Selector("updateRecording"), userInfo: nil, repeats: true)
  }

  // updates recording ui timer
  func updateRecording(){
    recordingTime += 1.0
    currentState = .Recording(seconds: recordingTime)
  }
  
  // stops recording and resets timer
  func stopRecording(){
    recordingTime = 0
    recordingTimer?.invalidate()
    recorder?.stop()
  }
  
  // starts uplading (error checking happens here)
  func startUploading(){
    
    guard let soundURL = soundURL else {
      print("no sound url")
      return
    }
    
    guard let data = NSData(contentsOfURL: soundURL) else {
      print("no data at sound url")
      return
    }
    
    uploadFile(data)
    
  }
  
  // uplades converted file to server
  func uploadFile(data: NSData){
    currentState = .Uploading(percent: 0)
    
    let url = NSURL(string: "")!
    let request = NSMutableURLRequest(URL: url)
    request.HTTPMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
    let session = NSURLSession(configuration: configuration, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
    let task = session.uploadTaskWithRequest(request, fromData: data)
    
    task.resume()
  }
  
}

extension ViewController: AVAudioRecorderDelegate {
  
  // notifies if file was recorded successfully and sends it to server
  
  func audioRecorderDidFinishRecording(recorder: AVAudioRecorder, successfully flag: Bool) {
    if flag {
      startUploading()
    } else {
      print("failed to record")
    }
  }
}

extension ViewController: NSURLSessionDataDelegate, NSURLSessionDelegate, NSURLSessionTaskDelegate {
  
  // updates current recording state based on state of network
  
  func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    
    let percent = Int((Double(totalBytesSent)/Double(totalBytesExpectedToSend)) * 100)
    currentState = .Uploading(percent: percent)
  }
  
  func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
    currentState = .Error(error: error?.localizedDescription ?? "")
  }
  
  func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
    currentState = .Ready
  }
  
}