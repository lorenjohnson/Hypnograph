//
//  ClipLibrary.swift
//  Hypnogram
//
//  Created by Loren Johnson on 15.11.25.
//


import Foundation

protocol ClipLibrary {
    var files: [VideoFile] { get }
    func randomClip(clipLength: Double) -> VideoClip?
}
