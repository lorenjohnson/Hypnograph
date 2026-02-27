//
//  EffectsStudioParameterBufferLayout.swift
//  Hypnograph
//

import Foundation

enum EffectsStudioScalarValueType {
    case float
    case int
    case uint
    case bool
}

struct EffectsStudioParamBufferMemberLayout {
    var name: String
    var offset: Int
    var size: Int
    var valueType: EffectsStudioScalarValueType
}

struct EffectsStudioParamBufferLayout {
    var length: Int
    var members: [EffectsStudioParamBufferMemberLayout]
}
