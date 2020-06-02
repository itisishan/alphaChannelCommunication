//
//  ViewController.swift
//  AlphaChannelCommunication
//
//  Created by Ishan Chatterjee on 5/29/20.
//  Copyright © 2020 Ishan Chatterjee. All rights reserved.
//

protocol Numeric {
    var asDouble: Double { get }
    init(_: Double)
}

extension Int: Numeric {var asDouble: Double { get {return Double(self)}}}
extension Float: Numeric {var asDouble: Double { get {return Double(self)}}}
extension Double: Numeric {var asDouble: Double { get {return Double(self)}}}
extension CGFloat: Numeric {var asDouble: Double { get {return Double(self)}}}

extension Array where Element: Numeric {

    var sd : Element { get {
        let sss = self.reduce((0.0, 0.0)){ return ($0.0 + $1.asDouble, $0.1 + ($1.asDouble * $1.asDouble))}
        let n = Double(self.count)
        return Element(sqrt(sss.1/n - (sss.0/n * sss.0/n)))
    }}
}

import UIKit
import AVKit

let roiSize = 100
let lengthForAverage = 10

let bitPeriod = 500 // milliseconds

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let rowOffset = 1080/2
    let columnOffset = 1920/2

    var xSecondTimer: Timer?

    var regionOfInterest: [[[UInt8]]] = Array(repeating: Array(repeating: Array(repeating: 0, count: 3), count: roiSize), count: roiSize)
    var regionOfInterestLast: [[[UInt8]]] = Array(repeating: Array(repeating: Array(repeating: 0, count: 3), count: roiSize), count: roiSize)
    
    var frameBrightness: Int = 0
    var frameBrightnessArray: [Int] = Array(repeating: 0, count: lengthForAverage)
    var firstTime = true
    
    var lastXElements = [Int]()
    var difference = 0
    
    var thresholded = -1
    var lastThresholded: Int = -1
    var bitArray = [Int]()
    var lastXBits = [Int]()
    
    var preamble = [0,1,0,1,0,1,0,1]
    var message = [0,0,0,1,0,1,1,1,0,1,0,1,0,1,0,1,0,1,1,1,0,0,0,0,1,0,1,0,1,0,1,0]

    struct time {
        static var lastTimeMs = 0.0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        
        
        let captureSession = AVCaptureSession()
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }
        captureSession.addInput(input)
        captureSession.startRunning()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        view.layer.addSublayer(previewLayer)
        
        previewLayer.frame = view.frame
        
        let dataOutput =  AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(dataOutput)
        
        xSecondTimer = Timer.scheduledTimer(timeInterval: (Double(bitPeriod)/1000),
                target: self,
                selector: #selector(ViewController.thresholdOutputAmplitudeInterval),
                userInfo: nil,
                repeats: true)
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("Camera was able to capture a frame:", Date())
        
        //guard let pixelBuffer:CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0));
        let int32Buffer = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuffer), to: UnsafeMutablePointer<UInt32>.self)
        
        var frameBrightnessSum = 0
        //print(pixelBuffer)
        for row in 0..<roiSize {
            for column in 0..<roiSize {
                let luma = int32Buffer[(row+rowOffset) * 1920 + (column+columnOffset)]
                
                let blue = UInt8(truncatingIfNeeded: luma)
                let green = UInt8(truncatingIfNeeded: (luma >> 8))
                let red = UInt8(truncatingIfNeeded: (luma >> 16))
                //let alpha = UInt8(truncatingIfNeeded: (luma >> 24))
                
                let pixel: [UInt8] = [blue, green, red]
                let pixelInt: [Int] = [Int(blue), Int(green), Int(red)]
                
                //regionOfInterestLast[row][column] = regionOfInterest[row][column]
                regionOfInterest[row][column] = pixel
                
                let pixelSum = pixelInt.reduce(0, +)
                frameBrightnessSum += pixelSum
            }
        }
        frameBrightness = frameBrightnessSum / (roiSize * roiSize)
        
        frameBrightnessArray.append(frameBrightness * 1000)
        
        lastXElements = Array(frameBrightnessArray[(frameBrightnessArray.endIndex-lengthForAverage) ..< frameBrightnessArray.endIndex])
        difference = (frameBrightnessArray[(frameBrightnessArray.endIndex-2)] - frameBrightnessArray[frameBrightnessArray.endIndex-1])
        print(frameBrightness, Double(lastXElements.sd), difference)
        //print(regionOfInterest)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
//        if let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
//            let ciimage = CIImage(cvImageBuffer: cvImageBuffer)
//            let context = CIContext()
//            if let cgImage = context.createCGImage(ciimage, from: ciimage.extent) {
//                frame = UIImage(cgImage: cgImage)
//            }
//        }
        
        //thresholdOutputAmplitude()
        if (difference > 10000) { thresholded = 1 }
        else if (difference < -10000) { thresholded = 0 }
        lastThresholded = thresholded
        
    }
    
    func thresholdOutput() {

        lastThresholded = thresholded
        if (lastXElements.sd > 1000) { thresholded = 1 }
        else { thresholded = 0 }
        //print(thresholded)
        
        if ((thresholded == 1) && ((CACurrentMediaTime() - time.lastTimeMs) > 0.24)) {
            bitArray.append(1)
            time.lastTimeMs = CACurrentMediaTime()
        }
        else if ((thresholded == 0) && ((CACurrentMediaTime() - time.lastTimeMs) > 0.24)) {
            bitArray.append(0)
            time.lastTimeMs = CACurrentMediaTime()
        }
    }
        
    func thresholdOutputAmplitude() {

        if (difference > 10000) { thresholded = 1 }
        else if (difference < -10000) { thresholded = 0 }
        
        lastThresholded = thresholded
        //print(thresholded)
        
        if ((thresholded == 1) && ((CACurrentMediaTime() - time.lastTimeMs) > (0.001 * Double(bitPeriod)))) {
            bitArray.append(1)
            print((CACurrentMediaTime() - time.lastTimeMs))
            time.lastTimeMs = CACurrentMediaTime()
        }
        else if ((thresholded == 0) && ((CACurrentMediaTime() - time.lastTimeMs) > (0.001 * Double(bitPeriod)))) {
            bitArray.append(0)
            print((CACurrentMediaTime() - time.lastTimeMs))

            time.lastTimeMs = CACurrentMediaTime()
        }
        else if ((thresholded == lastThresholded) && ((CACurrentMediaTime() - time.lastTimeMs) > (0.001 * Double(bitPeriod)))) {
            bitArray.append(lastThresholded)
            print((CACurrentMediaTime() - time.lastTimeMs))

            time.lastTimeMs = CACurrentMediaTime()
        }
        processBits()
    }
    
    @objc func thresholdOutputAmplitudeInterval() {
        
        if (thresholded == 1) {
            bitArray.append(1)

        }
        else if (thresholded == 0) {
            bitArray.append(0)

        }
        else if (thresholded == lastThresholded) {
            bitArray.append(lastThresholded)
        }
        processBits()
    }
    
    func processBits() {
        if (bitArray.count > preamble.count) {
            lastXBits = Array(bitArray[(bitArray.endIndex-preamble.count) ..< bitArray.endIndex])
            //print(bitArray)
        }

        if (lastXBits == preamble) {
            var sum = 0
            for index in 0..<message.count {
                if (bitArray[index] != message[index]) {
                    sum += 1
                }
            }
            let bitError = Double(sum)/Double(bitArray.count)
            print("Bit Error Rate: ",bitError)
            print("PREAMABLE DETECTED")
            bitArray = []
            lastXBits = []
            print(bitArray)
        }
    }

}

