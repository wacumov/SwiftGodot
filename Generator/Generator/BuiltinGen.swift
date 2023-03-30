//
//  BuiltinGen.swift
//  Generator
//
//  Created by Miguel de Icaza on 3/26/23.
//

import Foundation

func generateBuiltinCtors (_ ctors: [JGodotConstructor], typeName: String, typeEnum: String, members: [JGodotSingleton]?)
{
    for m in ctors {
        
        var args = ""
    
        let ptrName = "constructor\(m.index)"
        p ("static var \(ptrName): GDExtensionPtrConstructor = gi.variant_get_ptr_constructor (\(typeEnum), \(m.index))!\n")
        
        for arg in m.arguments ?? [] {
            if args != "" { args += ", " }
            args += getArgumentDeclaration(arg, eliminate: "", builtin: true)
        }
        
        b ("public init (\(args))") {
            // Determine if we have a constructors whose sole job is to initialize the members
            // of the struct, in that case, just do that, do not call into Godot.
            if let margs = m.arguments, let members, margs.count == members.count {
                var constructorMatchesFields = true
                for x in 0..<margs.count {
                    // This is so that we can match field `x` with `xAxis` in a few cases
                    if !(margs [x].name.starts (with: members [x].name) && margs [x].type == members [x].type) {
                        constructorMatchesFields = false
                        break
                    }
                }
                if constructorMatchesFields {
                    for x in 0..<margs.count {
                        p ("self.\(members [x].name) = \(escapeSwift (snakeToCamel (margs [x].name)))")
                    }
                    return
                }
            }
            let argPrepare = generateArgPrepare(m.arguments ?? [])
            if argPrepare != "" {
                p (argPrepare)
            }
            
            let ptrArgs = (m.arguments != nil) ? "&args" : "nil"
            
            // I used to have a nicer model, rather than everything having a
            // handle, I had a named handle, like "_godot_string"
            var ptr = isStructMap [typeName] ?? false ? "self" : "handle"
            
            // We need to initialize some variables before we call
            if let members {
                for x in members {
                    p ("self.\(x.name) = \(BuiltinJsonTypeToSwift (x.type)) ()")
                }
                // Another special case: empty constructors in generated structs (those we added fields for)
                // we just keep the manual initialization and do not call the constructor
                if m.arguments == nil {
                    return
                }
            }
            // Call
            p ("\(typeName).\(ptrName) (&\(ptr), \(ptrArgs))")
        }
    }
}

func generateBuiltinMethods (_ methods: [JGodotBuiltinClassMethod], _ typeName: String, _ typeEnum: String, isStruct: Bool)
{
    if methods.count > 0 {
        p ("\n/* Methods */\n")
    }
    for m in methods {
        if m.name == "repeat" {
            // TODO: Avoid clash for now
            continue
        }

        let ret = getGodotType(m.returnType ?? "", builtin: true)
        
        // TODO: problem caused by gobject_object being defined as "void", so it is not possible to create storage to that.
        if ret == "Object" {
            continue
        }
        let retSig = ret == "" ? "" : "-> \(ret)"
        var args = ""
    
        let ptrName = "method_\(m.name)"
        
        b ("static var \(ptrName): GDExtensionPtrBuiltInMethod = ", suffix: "()"){
            p ("let name = StringName (\"\(m.name)\")")
            p ("return gi.variant_get_ptr_builtin_method (\(typeEnum), &name.handle, \(m.hash))!")
        }
        
        for arg in m.arguments ?? [] {
            if args != "" { args += ", " }
            args += getArgumentDeclaration(arg, eliminate: "")
        }
        
        let has_return = m.returnType != nil
        
        b ("public\(isStruct ? "" : " final") func \(escapeSwift (snakeToCamel(m.name))) (\(args))\(retSig)") {
            let resultTypeName = "\(getGodotType (m.returnType ?? "", builtin: true))"
            if has_return {
                p ("var result: \(resultTypeName) = \(resultTypeName)()")
            }
            
            let argPrep = generateArgPrepare(m.arguments ?? [])
            if argPrep != "" {
                p (argPrep)
            }
            let ptrArgs = (m.arguments?.count ?? 0) > 0 ? "&args" : "nil"
            let ptrResult: String
            if has_return {
                let isStruct = isStructMap [m.returnType ?? ""] ?? false
                if isStruct {
                    ptrResult = "&result"
                } else {
                    ptrResult = "&result.handle"
                }
            } else {
                ptrResult = "nil"
            }
            
            if isStructMap [typeName] ?? false {
                p ("withUnsafePointer (to: self) { ptr in ")
                p ("    \(typeName).\(ptrName) (UnsafeMutableRawPointer (mutating: ptr), \(ptrArgs), \(ptrResult), \(m.arguments?.count ?? 0))")
                p ("}")
            } else {
                p ("\(typeName).\(ptrName) (&handle, \(ptrArgs), \(ptrResult), \(m.arguments?.count ?? 0))")
            }
            if has_return {
                // let cast = castGodotToSwift (m.returnType, "result")
                p ("return result")
            }
        }
    }
}

var builtinGodotTypeNames = Set<String>()

func generateBuiltinClasses (values: [JGodotBuiltinClass]) {
    func generateBuiltinClass (_ bc: JGodotBuiltinClass) {
        // TODO: isKeyed, hasDestrcturo,
        var kind: String
        if bc.members != nil {
            kind = "struct"
        } else {
            kind = "class"
        }
        builtinGodotTypeNames.insert(bc.name)
        let typeName = mapTypeName (bc.name)
        let typeEnum = "GDEXTENSION_VARIANT_TYPE_" + camelToSnake(bc.name).uppercased()
        b ("public \(kind) \(typeName)") {
            if bc.name == "String" {
                b ("public init (_ str: String)") {
                    p ("var vh: UnsafeMutableRawPointer?")
                    p ("gi.string_new_with_utf8_chars (&vh, str)")
                    p ("handle = OpaquePointer (vh)")
                }
            }
            if bc.name == "StringName" {
                // TODO: This is a little brittle, because I am
                // hardcoding the constructor1 here, it should
                // really produce this when it matches the kind
                // directly to be the one that takes a StringName
                // parameter
                b ("public init (fromPtr: UnsafeRawPointer?)") {
                    p ("var args: [UnsafeRawPointer?] = [")
                    p ("    fromPtr,")
                    p ("]")
                    p ("StringName.constructor1 (&handle, &args)")
                }
            }
            if kind == "class" {
                p ("var handle: OpaquePointer?")
            }
            if let members = bc.members {
                for x in members {
                    p ("var \(x.name): \(BuiltinJsonTypeToSwift (x.type))")
                }
            }

            if let enums = bc.enums {
                generateEnums(values: enums)
            }
            generateBuiltinCtors (bc.constructors, typeName: typeName, typeEnum: typeEnum, members: bc.members)
            generateBuiltinMethods(bc.methods ?? [], typeName, typeEnum, isStruct: kind == "struct")
        }
    }
    
    for bc in values {
        switch bc.name {
            // We do not generate code for a few types, we will bridge those instead
        case "int", "float", "bool":
            break
        default:
            generateBuiltinClass (bc)
        }
    }
}