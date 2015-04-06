//
//  CameraKit.swift
//  CameraKit
//
//  Created by Justin Makaila on 4/6/15.
//  Copyright (c) 2015 Present, Inc. All rights reserved.
//

import UIKit

public func cgImageFromSampleBuffer(sampleBuffer: CMSampleBufferRef) -> CGImageRef {
    let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    CVPixelBufferLockBaseAddress(imageBuffer, 0)
    
    let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    let bitmapInfo: CGBitmapInfo = (CGBitmapInfo.ByteOrder32Little | CGBitmapInfo.AlphaInfoMask)
    let newContext = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, bitmapInfo)
    
    let newImage = CGBitmapContextCreateImage(newContext)
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0)
    
    return newImage
}

public func imageFromSampleBuffer(sampleBuffer: CMSampleBufferRef) -> UIImage? {
    return UIImage(CGImage: cgImageFromSampleBuffer(sampleBuffer))
}