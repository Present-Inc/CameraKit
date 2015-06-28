//
//  CameraKit.swift
//  CameraKit
//
//  Created by Justin Makaila on 4/6/15.
//  Copyright (c) 2015 Present, Inc. All rights reserved.
//

import UIKit

public func cgImageFromSampleBuffer(sampleBuffer: CMSampleBufferRef) -> CGImageRef? {
    if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        CVPixelBufferLockBaseAddress(imageBuffer, 0)
        
        let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo: CGBitmapInfo = ([CGBitmapInfo.ByteOrder32Little, CGBitmapInfo.AlphaInfoMask])
        let newContext = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, bitmapInfo.rawValue)
        
        let newImage = CGBitmapContextCreateImage(newContext)
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0)
        
        return newImage
    }
    
    return nil
}

public func imageFromSampleBuffer(sampleBuffer: CMSampleBufferRef) -> UIImage? {
    if let cgImage = cgImageFromSampleBuffer(sampleBuffer) {
        return UIImage(CGImage: cgImage)
    }
    
    return nil
}