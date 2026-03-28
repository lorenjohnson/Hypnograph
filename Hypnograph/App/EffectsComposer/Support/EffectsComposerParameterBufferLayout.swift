//
//  EffectsComposerParameterBufferLayout.swift
//  Hypnograph
//

import Foundation

enum EffectsComposerScalarValueType {
    case float
    case int
    case uint
    case bool
}

struct EffectsComposerParamBufferMemberLayout {
    var name: String
    var offset: Int
    var size: Int
    var valueType: EffectsComposerScalarValueType
}

struct EffectsComposerParamBufferLayout {
    var length: Int
    var members: [EffectsComposerParamBufferMemberLayout]
}
