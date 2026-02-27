//
//  EffectsEditorField.swift
//  Hypnograph
//

enum EffectsEditorField: Hashable {
    case effectList           // Effect selection list
    case parameterList        // Parameter sliders area
    case effectName           // Effect name text field
    case parameterText(Int)   // Parameter text field at index
    case effectCheckbox(Int)  // Effect enable/disable checkbox at index
}
