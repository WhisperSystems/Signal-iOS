#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

from __future__ import print_function
import os
import sys
import subprocess
import datetime
import argparse
import commands
import re
import json
import sds_common
from sds_common import fail
import tempfile
import shutil

git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())


def ows_getoutput(cmd):
    proc = subprocess.Popen(cmd,
        stdout = subprocess.PIPE,
        stderr = subprocess.PIPE,
    )
    stdout, stderr = proc.communicate()

    return proc.returncode, stdout, stderr


class LineProcessor:
    def __init__(self, text):
        self.lines = text.split('\n')

    def hasNext(self):
        return len(self.lines) > 0

    def next(self, should_pop = False):
        if len(self.lines) == 0:
            return None
        line = self.lines[0]
        if should_pop:
            self.lines = self.lines[1:]
        return line

    def popNext(self):
        return self.next(should_pop = True)

counter = 0
def next_counter():
    global counter
    counter = counter + 1
    return counter

class ParsedClass:
    def __init__(self, name):
        # print '--- instantiating ParsedClass', name
        self.name = name
        self.is_implemented = False
        self.property_map = {}
        self.super_class_name = None
        self.counter = next_counter()
        self.finalize_method_name = None
        self.namespace = None
        self.protocol_names = []

    def get_property(self, name):
        result = self.property_map.get(name)
        if result is None:
            result = self.get_inherited_property(name)
        return result

    def add_property(self, property):
        self.property_map[property.name] = property

    def properties(self):
        result = []
        for name in sorted(self.property_map.keys()):
            result.append(self.property_map[name])
        return result

    def property_names(self):
        return sorted(self.property_map.keys())

    def inherit_from_protocol(self, namespace, protocol_name):
        self.namespace = namespace
        self.protocol_names.append(protocol_name)

    def get_inherited_property(self, name):
        for protocol in self.class_protocols():
            result = protocol.get_property(name)
            if result is not None:
                return result
        return None

    def all_properties(self):
        result = self.properties()
        # We need to include any properties synthesized by this class
        # but declared in a protocol.
        for protocol in self.class_protocols():
            result.extend(protocol.all_properties())
        return result

    def class_protocols(self):
        result = []
        for protocol_name in self.protocol_names:
            if protocol_name == self.name:
                # There are classes that implement a protocol of the same name, e.g. MTLModel
                # Ignore them.
                continue

            # print 'get_inherited_property:', name, self.name, protocol_name

            protocol = self.namespace.find_class(protocol_name)
            if protocol is None:
                if protocol_name.startswith('NS') or protocol_name.startswith('AV') or protocol_name.startswith('UI') or protocol_name.startswith('MF') or protocol_name.startswith('UN') or protocol_name.startswith('CN'):
                    # Ignore built in protocols.
                    continue
                print('clazz:', self.name)
                print('file_path:', file_path)
                fail('Missing protocol:', protocol_name)

            result.append(protocol)

        return result


class ParsedProperty:
    def __init__(self, name, objc_type, is_optional):
        self.name = name
        self.objc_type = objc_type
        self.is_optional = is_optional
        self.is_not_readonly = False
        self.is_synthesized = False


class Namespace:
    def __init__(self):
        self.class_map = {}

    def upsert_class(self, class_name):
        clazz = self.class_map.get(class_name)
        if clazz is None:
            clazz = ParsedClass(class_name)
            self.class_map[class_name] = clazz
        return clazz

    def find_class(self, class_name):
        clazz = self.class_map.get(class_name)
        return clazz

    def class_names(self):
        return sorted(self.class_map.keys())


split_objc_ast_prefix_regex = re.compile(r'^([ |\-`]*)(.+)$')

# The AST emitted by clang uses punctuation to indicate the AST hierarchy.
# This function strips that out.
def split_objc_ast_prefix(line):
    match = split_objc_ast_prefix_regex.search(line)
    if match is None:
        fail('Could not match line:', line)
    prefix = match.group(1)
    remainder = match.group(2)
    # print 'prefix', prefix
    # print 'remainder', remainder
    return prefix, remainder


def process_objc_ast(namespace, file_path, raw_ast):
    m_filename = os.path.basename(file_path)
    print('m_filename:', m_filename)
    file_base, file_extension = os.path.splitext(m_filename)
    if file_extension != '.m':
        fail('Bad file extension:', file_extension)
    h_filename = file_base + '.h'
    print('h_filename:', h_filename)

    # TODO: Remove
    lines = raw_ast.split('\n')
    # lines = lines[-1000:]
    raw_ast = '\n'.join(lines)

    lines = LineProcessor(raw_ast)
    while lines.hasNext():
        line = lines.popNext()
        # print 'line:', line
        prefix, remainder = split_objc_ast_prefix(line)

        if remainder.startswith('ObjCInterfaceDecl '):
            # |-ObjCInterfaceDecl 0x112510490 <SignalDataStoreCommon/ObjCMessage.h:14:1, line:25:2> line:14:12 ObjCMessage
            # print 'interface', line
            process_objc_interface(namespace, file_path, lines, prefix, remainder)
        elif remainder.startswith('ObjCCategoryDecl '):
            # |-ObjCCategoryDecl 0x112510d58 <SignalDataStoreCommon/ObjCMessage.m:18:1, line:22:2> line:18:12
            # print 'category', line
            process_objc_category(namespace, file_path, lines, prefix, remainder)
        elif remainder.startswith('ObjCImplementationDecl '):
            # `-ObjCImplementationDecl 0x112510f20 <line:24:1, line:87:1> line:24:17 ObjCMessage
            # print 'implementation', line
            process_objc_implementation(namespace, file_path, lines, prefix, remainder)
        elif remainder.startswith('ObjCProtocolDecl '):
            # `-ObjCImplementationDecl 0x112510f20 <line:24:1, line:87:1> line:24:17 ObjCMessage
            # print 'implementation', line
            process_objc_protocol_decl(namespace, file_path, lines, prefix, remainder)
        # TODO: Category impl.
        elif remainder.startswith('TypedefDecl '):
            # `-ObjCImplementationDecl 0x112510f20 <line:24:1, line:87:1> line:24:17 ObjCMessage
            # print 'implementation', line
            process_objc_type_declaration(namespace, file_path, lines, prefix, remainder)
        elif remainder.startswith('EnumDecl '):
            # `-ObjCImplementationDecl 0x112510f20 <line:24:1, line:87:1> line:24:17 ObjCMessage
            # print 'implementation', line
            process_objc_enum_declaration(namespace, file_path, lines, prefix, remainder)


# |-EnumDecl 0x7fd576047310 </Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS12.2.sdk/System/Library/Frameworks/CoreFoundation.framework/Headers/CFAvailability.h:127:43, /Users/matthew/code/workspace/ows/Signal-iOS-2/SignalServiceKit/src/Messages/TSCall.h:12:29> col:29 RPRecentCallType 'NSUInteger':'unsigned long'
# | `-EnumExtensibilityAttr 0x7fd5760473f0 </Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS12.2.sdk/System/Library/Frameworks/CoreFoundation.framework/Headers/CFAvailability.h:116:45, col:68> Open
# |-TypedefDecl 0x7fd576047488 </Users/matthew/code/workspace/ows/Signal-iOS-2/SignalServiceKit/src/Messages/TSCall.h:12:1, col:29> col:29 referenced RPRecentCallType 'enum RPRecentCallType':'enum RPRecentCallType'
# | `-ElaboratedType 0x7fd576047430 'enum RPRecentCallType' sugar
# |   `-EnumType 0x7fd5760473d0 'enum RPRecentCallType'
# |     `-Enum 0x7fd576047518 'RPRecentCallType'
# |-EnumDecl 0x7fd576047518 prev 0x7fd576047310 </Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS12.2.sdk/System/Library/Frameworks/CoreFoundation.framework/Headers/CFAvailability.h:127:90,
process_objc_enum_declaration_regex = re.compile(r"^.+? ([^ ]+) '([^']+)':'([^']+)'$")
# process_objc_enum_declaration_regex = re.compile(r"^.+?'([^']+)'(:'([^']+)')?$")

enum_type_map = {}

def process_objc_enum_declaration(namespace, file_path, lines, prefix, remainder):
    print('\t', 'enum_declaration', remainder)

    match = process_objc_enum_declaration_regex.search(remainder)
    if match is None:
        print('file_path:', file_path)
        print('Could not match line:', remainder)
        return
    type1 = get_match_group(match, 1)
    type2 = get_match_group(match, 2)
    type3 = get_match_group(match, 3)

    # print 'enum?', type1, type2, type3

    if type1.startswith('line:'):
        print('Ignoring invalid enum(1):', type1, type2, type3)
        return
    if type1 in enum_type_map:
        return
    enum_type_map[type1] = type2
    print('enum_type_map', enum_type_map)


# |-TypedefDecl 0x7f8d8fb44748 <line:12:1, line:22:3> col:3 referenced RPRecentCallType 'enum RPRecentCallType':'RPRecentCallType'
process_objc_type_declaration_regex = re.compile(r"^.+?'([^']+)'(:'([^']+)')?$")

def process_objc_type_declaration(namespace, file_path, lines, prefix, remainder):
    print('\t', 'type_declaration', remainder)

    match = process_objc_type_declaration_regex.search(remainder)
    if match is None:
        print('file_path:', file_path)
        fail('Could not match line:', remainder)
    type1 = get_match_group(match, 1)
    type2 = get_match_group(match, 2)
    type3 = get_match_group(match, 3)

    if type1 is None or type3 is None:
        return
    is_enum = (type1 == 'enum ' + type3)
    if not is_enum:
        return

    # print 'type_declaration:', type1, type2, type3

    if type3.startswith('line:'):
        print('Ignoring invalid enum(2):', type1, type2, type3)
        return
    if type3 not in enum_type_map:
        print('Enum has unknown type:', type3)
        enum_type = 'NSUInteger'
    else:
        enum_type = enum_type_map[type3]
    enum_type_map[type3] = enum_type


# |-ObjCInterfaceDecl 0x10f5d2b60 <SignalDataStoreCommon/ObjCBaseModel.h:15:1, col:8> col:8 SDSDataStore
# |-ObjCInterfaceDecl 0x10f5d2c10 <line:17:1, line:29:2> line:17:12 ObjCBaseModel
# | |-ObjCPropertyDecl 0x10f5d2d40 <line:19:1, col:43> col:43 uniqueId 'NSString * _Nonnull':'NSString *' readonly nonatomic
# ...
# |-ObjCInterfaceDecl 0x10f5d3490 <SignalDataStoreCommon/ObjCMessage.h:14:1, line:25:2> line:14:12 ObjCMessage
# | |-super ObjCInterface 0x10f5d2c10 'ObjCBaseModel'
# | |-ObjCImplementation 0x10f5d3f20 'ObjCMessage'
# | |-ObjCPropertyDecl 0x10f5d35d0 <line:16:1, col:43> col:43 body 'NSString * _Nonnull':'NSString *' readonly nonatomic strong
def process_objc_interface(namespace, file_path, lines, decl_prefix, decl_remainder):
    # print '\t', 'interface'

    # |-ObjCInterfaceDecl 0x10ab2fd58 </Users/matthew/code/workspace/ows/Signal-iOS-2/SignalDataStore/SignalDataStoreCommon/ObjCMessageWAuthor.h:13:1, line:26:2> line:13:12 ObjCMessageWAuthor
    # | |-super ObjCInterface 0x10ab2f490 'ObjCMessage'

    super_class_name = None
    if lines.hasNext():
        line = lines.next()
        prefix, remainder = split_objc_ast_prefix(line)
        if len(prefix) > len(decl_prefix):
            splits = remainder.split(' ')
            if len(splits) >= 2 and splits[0] == 'super':
                # print 'line', line
                # print 'splits', splits
                super_class_name = splits[-1].strip()
                if super_class_name.startswith("'") and super_class_name.endswith("'"):
                    super_class_name = super_class_name[1:-1]

    process_objc_class(namespace, file_path, lines, decl_prefix, decl_remainder, super_class_name=super_class_name)

# |-ObjCCategoryDecl 0x10f5d3d58 <SignalDataStoreCommon/ObjCMessage.m:18:1, line:22:2> line:18:12
# | |-ObjCInterface 0x10f5d3490 'ObjCMessage'
# | |-ObjCPropertyDecl 0x10f5d3e20 <line:20:1, col:43> col:43 ignore 'NSString * _Nonnull':'NSString *' readonly nonatomic strong
# | `-ObjCMethodDecl 0x10f5d3e98 <col:43> col:43 implicit - ignore 'NSString * _Nonnull':'NSString *'
def process_objc_category(namespace, file_path, lines, decl_prefix, decl_remainder):
    # print '\t', 'category'

    # |-ObjCCategoryDecl 0x1092f8440 <line:76:1, line:81:2> line:76:12 SomeCategory
    # | |-ObjCInterface 0x1092f5d58 'ObjCMessageWAuthor'
    # | |-ObjCCategoryImpl 0x1092f8608 'SomeCategory'
    # | |-ObjCPropertyDecl 0x1092f8508 <line:79:1, col:53> col:53 fakeProperty2 'NSString * _Nullable':'NSString *' readonly nonatomic
    # | `-ObjCMethodDecl 0x1092f8580 <col:53> col:53 implicit - fakeProperty2 'NSString * _Nullable':'NSString *'
    if not lines.hasNext():
        fail('Category missing interface.')
    line = lines.next()
    prefix, remainder = split_objc_ast_prefix(line)
    if len(prefix) <= len(decl_prefix):
        fail('Category missing interface.')
    class_name = remainder.split(' ')[-1]
    if class_name.startswith("'") and class_name.endswith("'"):
        class_name = class_name[1:-1]

    process_objc_class(namespace, file_path, lines, decl_prefix, decl_remainder, custom_class_name=class_name)

# |-ObjCCategoryDecl 0x10f5d3d58 <SignalDataStoreCommon/ObjCMessage.m:18:1, line:22:2> line:18:12
# | |-ObjCInterface 0x10f5d3490 'ObjCMessage'
# | |-ObjCPropertyDecl 0x10f5d3e20 <line:20:1, col:43> col:43 ignore 'NSString * _Nonnull':'NSString *' readonly nonatomic strong
# | `-ObjCMethodDecl 0x10f5d3e98 <col:43> col:43 implicit - ignore 'NSString * _Nonnull':'NSString *'
def process_objc_implementation(namespace, file_path, lines, decl_prefix, decl_remainder):
    # print '\t', 'implementation'
    clazz = process_objc_class(namespace, file_path, lines, decl_prefix, decl_remainder)
    if clazz is not None:
        clazz.is_implemented = True

def process_objc_protocol_decl(namespace, file_path, lines, decl_prefix, decl_remainder):
    print('\t', 'protocol decl', decl_remainder)
    clazz = process_objc_class(namespace, file_path, lines, decl_prefix, decl_remainder)
    if clazz is not None:
        clazz.is_implemented = True

# |-ObjCCategoryDecl 0x10f5d3d58 <SignalDataStoreCommon/ObjCMessage.m:18:1, line:22:2> line:18:12
# | |-ObjCInterface 0x10f5d3490 'ObjCMessage'
# | |-ObjCPropertyDecl 0x10f5d3e20 <line:20:1, col:43> col:43 ignore 'NSString * _Nonnull':'NSString *' readonly nonatomic strong
# | `-ObjCMethodDecl 0x10f5d3e98 <col:43> col:43 implicit - ignore 'NSString * _Nonnull':'NSString *'
def process_objc_class(namespace, file_path, lines, decl_prefix, decl_remainder, custom_class_name=None, super_class_name=None):
    if custom_class_name is not None:
        class_name = custom_class_name
    else:
        class_name = decl_remainder.split(' ')[-1]
    # print '\t', 'class_name', class_name

    clazz = namespace.upsert_class(class_name)

    if super_class_name is not None:
        if clazz.super_class_name is None:
            clazz.super_class_name = super_class_name
        elif clazz.super_class_name != super_class_name:
            fail("super_class_name does not match:", clazz.super_class_name, super_class_name)

    while lines.hasNext():
        line = lines.next()
        prefix, remainder = split_objc_ast_prefix(line)
        if len(prefix) <= len(decl_prefix):
            # Declaration is over.
            return clazz

        line = lines.popNext()
        # print '\t', 'interface', 'line', line


        # print '\t', '\t', 'remainder', remainder

        # | |-ObjCPropertyDecl 0x10f5d2d40 <line:19:1, col:43> col:43 uniqueId 'NSString * _Nonnull':'NSString *' readonly nonatomic

        """
        TODO: We face interesting choices about how to process:

        * properties
        * private properties
        * properties with renamed ivars
        * ivars without properties
        * properties not backed by ivars (e.g. actually accessors).
        """
        # print 'remainder', remainder
        if remainder.startswith('ObjCPropertyDecl '):
            # print 'property ?', line
            process_objc_property(clazz, prefix, file_path, line, remainder)
        elif remainder.startswith('ObjCPropertyImplDecl '):
            # print 'property impl', line
            process_objc_property_impl(clazz, prefix, file_path, line, remainder)
        elif remainder.startswith('ObjCMethodDecl '):
            # print 'property impl', line
            process_objc_method_decl(clazz, prefix, file_path, line, remainder)
        elif remainder.startswith('ObjCProtocol '):
            # print 'property impl', line
            process_objc_protocol(namespace, clazz, prefix, file_path, line, remainder)

    return clazz

process_objc_method_decl_regex = re.compile(r" - (sdsFinalize[^ ]*?) 'void'$")

def process_objc_method_decl(clazz, prefix, file_path, line, remainder):
    # print '\t\t', 'process_objc_property_impl', remainder

    match = process_objc_method_decl_regex.search(remainder)
    if match is None:
        return
    method_name = match.group(1).strip()
    clazz.finalize_method_name = method_name


# | |-ObjCProtocol 0x7f879888b8a8 'AppContext'
process_objc_protocol_regex = re.compile(r" '([^']+)'$")

def process_objc_protocol(namespace, clazz, prefix, file_path, line, remainder):
    # print '\t\t', 'process_objc_property_impl', remainder

    match = process_objc_protocol_regex.search(remainder)
    if match is None:
        return
    protocol_name = match.group(1).strip()
    clazz.inherit_from_protocol(namespace, protocol_name)

    # protocol = namespace.find_class(protocol_name)
    # if protocol is None:
    #     if protocol_name.startswith('NS'):
    #         # Ignore built in protocols.
    #         return
    #     print 'clazz:', clazz.name
    #     print 'file_path:', file_path
    #     fail('Missing protocol:', protocol_name)
    #
    # clazz.inherit_from_protocol(protocol)


# | |-ObjCPropertyImplDecl 0x1092f6d68 <col:1, col:13> col:13 someSynthesizedProperty synthesize
# | |-ObjCPropertyImplDecl 0x1092f6f18 <col:1, col:35> col:13 someRenamedProperty synthesize
# | |-ObjCPropertyImplDecl 0x1092f7698 <<invalid sloc>, col:53> <invalid sloc> author synthesize
# | `-ObjCPropertyImplDecl 0x1092f77f8 <<invalid sloc>, col:53> <invalid sloc> somePrivateOptionalString synthesize
#
# ObjCPropertyDecl 0x7fc37e08f800 <line:37:1, col:28> col:28 shouldThreadBeVisible 'int' assign readwrite nonatomic unsafe_unretained
process_objc_property_impl_regex = re.compile(r"^.+ ([^ ]+) synthesize$")

def process_objc_property_impl(clazz, prefix, file_path, line, remainder):
    # print '\t\t', 'process_objc_property_impl', remainder

    match = process_objc_property_impl_regex.search(remainder)
    if match is None:
        print('file_path:', file_path)
        fail('Could not match line:', line)
    property_name = match.group(1).strip()
    property = clazz.get_property(property_name)
    if property is None:
        if clazz.name == 'AppDelegate' and property_name == 'window':
            # We can't parse properties synthesized locally but
            # declared in a protocol defined in the iOS frameworks.
            # So, special case these propert(y/ies) - we don't need
            # to handle them.
            return

        print('file_path:', file_path)
        print('line:', line)
        print('\t', 'clazz', clazz.name, clazz.counter)
        print('\t', 'property_name', property_name)
        for name in clazz.property_names():
            print('\t\t', name)
        fail("Can't find property:", property_name)
    else:
        print('property synthesized', line)
        property.is_synthesized = True


# | |-ObjCPropertyDecl 0x11250fd40 <line:19:1, col:43> col:43 uniqueId 'NSString * _Nonnull':'NSString *' readonly nonatomic
# | |-ObjCPropertyDecl 0x116afde80 <line:15:1, col:38> col:38 isUnread 'BOOL':'signed char' readonly nonatomic
#
# | |-ObjCPropertyDecl 0x7f8157089a00 <line:37:1, col:28> col:28 shouldThreadBeVisible 'int' assign readwrite nonatomic unsafe_unretained
#
# | |-ObjCPropertyDecl 0x7faf139af8e0 <line:37:1, col:28> col:28 shouldThreadBeVisible 'BOOL':'bool' assign readwrite nonatomic unsafe_unretained
# | |-ObjCPropertyDecl 0x7f879889f460 <line:46:1, col:40> col:40 mainWindow 'UIWindow * _Nullable':'UIWindow *' readwrite atomic strong
process_objc_property_regex = re.compile(r"^.+<.+> col:\d+(.+?)'(.+?)'(:'(.+)')?(.+)$")


# This convenience function handles None results and strips.
def get_match_group(match, index):
    group = match.group(index)
    if group is None:
        return ""
    return group.strip()


def process_objc_property(clazz, prefix, file_path, line, remainder):

    match = process_objc_property_regex.search(remainder)
    if match is None:
        print('file_path:', file_path)
        print('remainder:', remainder)
        fail('Could not match line:', line)
    property_name = match.group(1).strip()
    property_type_1 = get_match_group(match, 2)
    property_type_2 = get_match_group(match, 4)
    property_keywords = match.group(5).strip().split(' ')

    is_optional = (property_type_2 + ' _Nullable') == property_type_1
    is_readonly = 'readonly' in property_keywords

    property_type = property_type_2
    if len(property_type_2) < 1:
        property_type = property_type_1

    primitive_types = (
        'BOOL',
        'NSInteger',
        'NSUInteger',
        'uint64_t',
        'int64_t'
    )
    if property_type_1 in primitive_types:
        property_type = property_type_1
    # property_type = property_type_1

    print('\t', property_name, 'property_type', property_type, 'property_type1', property_type_1, 'property_type2', property_type_2, 'property_type', property_type)

    property = clazz.get_property(property_name)
    if property is None:

        property = ParsedProperty(property_name, property_type, is_optional)
        # print 'property found', line
        clazz.add_property(property)
    else:
        if property.name != property_name:
            fail("Property names don't match", property.name, property_name)
        if property.is_optional != is_optional:
            if clazz.name.startswith('DD'):
                # CocoaLumberjack has nullability consistency issues.
                # Ignore them.
                return
            print('file_path:', file_path)
            print('clazz:', clazz.name)
            fail("Property is_optional don't match", property_name)
        if property.objc_type != property_type:
            # There's a common pattern of using a mutable private property
            # and exposing a non-mutable public property to prevent
            # external modification of the property.
            if property_type.startswith('NSMutable') and property.objc_type == 'NS' + property_type[len('NSMutable'):]:
                property.objc_type = property_type
            else:
                print('file_path:', file_path)
                print('remainder:', remainder)
                print('property.objc_type:', property.objc_type)
                print('property_type:', property_type)
                print('property_name:', property_name)
                fail("Property types don't match", property.objc_type, property_type)


    if not is_readonly:
        property.is_not_readonly = True


def emit_output(file_path, namespace):
    classes = []
    for class_name in namespace.class_names():
        clazz = namespace.upsert_class(class_name)
        if not clazz.is_implemented:
            if not class_name.startswith('NS'):
                # print 'Ignoring class:', class_name
                pass
            continue

        properties = []

        for property in clazz.all_properties():
            if not property.is_synthesized:
                print('\t', 'Ignoring property:', property.name)
                continue

            property_dict = {
                'name': property.name,
                'objc_type': property.objc_type,
                'is_optional': property.is_optional,
                'class_name': class_name,
                # This might not be necessary, thanks to is_synthesized
                # 'is_readonly': (not property.is_not_readonly),
            }

            properties.append(property_dict)

        class_dict = {
            'name': class_name,
            'properties': properties,
            'filepath': sds_common.sds_to_relative_path(file_path),
            'finalize_method_name': clazz.finalize_method_name,
        }
        if clazz.super_class_name is not None:
            class_dict['super_class_name'] = clazz.super_class_name
        classes.append(class_dict)

    enums = enum_type_map

    root = {
        'classes': classes,
        'enums': enums,
    }

    return json.dumps(root, sort_keys=True, indent=4)


# We need to include search paths for every
# non-framework header.
def find_header_include_paths(include_path):
    result = []

    def add_dir_if_has_header(dir_path):
        # Only include subdirectories with header files.
        has_header = False
        for filename in os.listdir(dir_path):
            if filename.endswith('.h'):
                has_header = True
                break
        # has_header = True
        if has_header:
            result.append('-I' + dir_path)
        else:
            print('Ignoring:', dir_path)

    # Add root if necessary.
    add_dir_if_has_header(include_path)

    for rootdir, dirnames, filenames in os.walk(include_path):
        for dirname in dirnames:
            dir_path = os.path.abspath(os.path.join(rootdir, dirname))
            add_dir_if_has_header(dir_path)

    return result


# --- Modules

# Framework compilation gathers all framework headers
# in an include directory with the framework name, so
# that headers can be included like so:
#
# #import <framework_name/header_name.h>
#
# For example:
#
# #import <SignalServiceKit/OWSFailedAttachmentDownloadsJob.h>
#
# To simulate this, we walk the Pods directory and copy
# headers into per-framework directories.

def copy_module_headers(src_dir_path, module_name, module_header_dir_path):
    dst_dir_path = os.path.join(module_header_dir_path, module_name)
    os.mkdir(dst_dir_path)

    for rootdir, dirnames, filenames in os.walk(src_dir_path):
        for filename in filenames:
            if not filename.endswith('.h'):
                continue
            src_file_path = os.path.abspath(os.path.join(rootdir, filename))
            dst_file_path = os.path.abspath(os.path.join(dst_dir_path, filename))
            # print '\t', 'Copying:', src_file_path
            # print '\t\t', 'To:', dst_file_path
            shutil.copyfile(src_file_path, dst_file_path)


def gather_pod_headers(pods_dir_path, module_header_dir_path):

    for dirname in os.listdir(pods_dir_path):
        src_dir_path = os.path.join(pods_dir_path, dirname)
        if not os.path.isdir(src_dir_path):
            continue

        copy_module_headers(src_dir_path, dirname, module_header_dir_path)


def gather_module_headers(pods_dir_path):
    # Make a temp directory to gather framework headers in.
    module_header_dir_path = tempfile.mkdtemp()
    # print 'pod_header_dir_path', pod_header_dir_path

    gather_pod_headers(pods_dir_path, module_header_dir_path)

    for project_name in (
        'SignalServiceKit',
        'SignalMessaging',
        'Signal',
        ):
        src_dir_path = os.path.join(git_repo_path, project_name)
        copy_module_headers(src_dir_path, project_name, module_header_dir_path)

    return module_header_dir_path


# --- PCH


def get_pch_include(file_path):
    print('file_path', file_path)
    ssk_path = os.path.join(git_repo_path, 'SignalServiceKit') + os.sep
    sm_path = os.path.join(git_repo_path, 'SignalMessaging') + os.sep
    s_path = os.path.join(git_repo_path, 'Signal') + os.sep
    sae_path = os.path.join(git_repo_path, 'SignalShareExtension') + os.sep
    print('ssk_path', ssk_path)
    print('sm_path', sm_path)
    print('s_path', s_path)
    print('sae_path', sae_path)
    if file_path.startswith(ssk_path):
        return os.path.join(git_repo_path, "Pods/Target Support Files/SignalServiceKit/SignalServiceKit-prefix.pch")
    elif file_path.startswith(sm_path):
        return os.path.join(git_repo_path, "SignalMessaging/SignalMessaging-Prefix.pch")
    elif file_path.startswith(s_path):
        return os.path.join(git_repo_path, "Signal/Signal-Prefix.pch")
    elif file_path.startswith(sae_path):
        return os.path.join(git_repo_path, "SignalShareExtension/SignalShareExtension-Prefix.pch")
    else:
        fail("Couldn't determine .pch for file:", file_path)


# --- Processing


def process_objc(file_path, swift_bridging_path, intermediates):
    module_header_dir_path = gather_module_headers('Pods')
    pch_include = get_pch_include(file_path)

    # These clang args can be found by building our workspace and looking at how XCode invokes clang.
    clang_args = '-arch arm64 -fmessage-length=0 -fdiagnostics-show-note-include-stack -fmacro-backtrace-limit=0 -std=gnu11 -fobjc-arc -fobjc-weak -fmodules -gmodules -fmodules-prune-interval=86400 -fmodules-prune-after=345600 -Wnon-modular-include-in-framework-module -Werror=non-modular-include-in-framework-module -fapplication-extension -Wno-trigraphs -fpascal-strings -O0 -fno-common -Wno-missing-field-initializers -Wno-missing-prototypes -Werror=return-type -Wdocumentation -Wunreachable-code -Wno-implicit-atomic-properties -Werror=deprecated-objc-isa-usage -Wno-objc-interface-ivars -Werror=objc-root-class -Wno-arc-repeated-use-of-weak -Wimplicit-retain-self -Wduplicate-method-match -Wno-missing-braces -Wparentheses -Wswitch -Wunused-function -Wno-unused-label -Wno-unused-parameter -Wunused-variable -Wunused-value -Wempty-body -Wuninitialized -Wconditional-uninitialized -Wno-unknown-pragmas -Wno-shadow -Wno-four-char-constants -Wno-conversion -Wconstant-conversion -Wint-conversion -Wbool-conversion -Wenum-conversion -Wno-float-conversion -Wnon-literal-null-conversion -Wobjc-literal-conversion -Wshorten-64-to-32 -Wpointer-sign -Wno-newline-eof -Wno-selector -Wno-strict-selector-match -Wundeclared-selector -Wdeprecated-implementations'.split(' ')

    command = [
        'xcrun',
        '--show-sdk-path',
        '--sdk',
        'iphoneos',
    ]
    exit_code, output, error_output = ows_getoutput(command)
    if int(exit_code) != 0:
        fail('Could not find iOS SDK.')
    iphoneos_sdk_path = output.strip()

    # TODO: We'll never repro the correct search paths, so clang will always emit errors.
    #       We'll want to ignore these errors without silently failing.
    command = [
        'clang',
        '-x',
        'objective-c',
        '-Xclang',
        '-ast-dump',
        '-fobjc-arc',
        ] + clang_args + [
        '-isysroot',
        iphoneos_sdk_path,
        ] + find_header_include_paths('SignalServiceKit/src') + [
        ] + find_header_include_paths('SignalMessaging') + [
        # ] + find_header_include_paths('Pods') + [
        ('-I' + module_header_dir_path),
        ('-I' + swift_bridging_path),
        '-I/Users/matthew/code/workspace/ows/Signal-iOS-2/Pods/SignalCoreKit/SignalCoreKit',
        '-include',
        pch_include,
        file_path,
        # '|',
        # 'sed',
        # "$'s,\x1b\\[[0-9;]*[a-zA-Z],,g'",
        # '>',
        # 'test4.txt'
    ]
    for part in command:
        print('\t', part)
    # command = ' '.join(command).strip()
    # print 'command', command
    # output = commands.getoutput(command)

    # command = ' '.join(command).strip()
    print('command', command)
    exit_code, output, error_output = ows_getoutput(command)
    print('exit_code:', exit_code)
    print('error_output:', error_output)
    # print 'output:', len(output)

    # exit(1)

    output = output.strip()
    raw_ast = output

    if intermediates:
        intermediate_file_path = file_path + '.ast'
        print('Writing intermediate:', intermediate_file_path)
        with open(intermediate_file_path, 'wt') as f:
            f.write(raw_ast)
    print('raw_ast:', len(raw_ast))

    namespace = Namespace()

    process_objc_ast(namespace, file_path, raw_ast)

    output = emit_output(file_path, namespace)

    print('output', output)

    parsed_file_path = file_path + sds_common.SDS_JSON_FILE_EXTENSION
    print('parsed_file_path', parsed_file_path)
    with open(parsed_file_path, 'wt') as f:
        f.write(output)


def process_file(file_path, swift_bridging_path, intermediates):
    filename = os.path.basename(file_path)
    # print 'filename', filename
    _, file_extension = os.path.splitext(filename)
    if file_extension == '.m':
        # print 'filename:', filename
        process_objc(file_path, swift_bridging_path, args.intermediates)


# ---

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Parse Objective-C AST.')
    parser.add_argument('--src-path', required=True, help='used to specify a path to process.')
    parser.add_argument('--swift-bridging-path', required=True, help='used to specify a path to process.')
    parser.add_argument('--intermediates', action='store_true', help='if set, will write intermediate files')
    args = parser.parse_args()

    src_path = os.path.abspath(args.src_path)
    swift_bridging_path = os.path.abspath(args.swift_bridging_path)


    # SDS code generation uses clang to parse the AST of Objective-C files.
    # We're parsing these files outside the context of an XCode workspace,
    # so many things won't work - unless do some legwork.
    #
    # * Compiling of dependencies.
    # * Workspace include and framework search paths.
    # * Auto-generated files, like -Swift.h bridging headers.
    # * .pch files.

    if os.path.isfile(src_path):
        process_file(src_path, swift_bridging_path, args.intermediates)
    else:
        # First clear out existing .sdsjson files.
        for rootdir, dirnames, filenames in os.walk(src_path):
            for filename in filenames:
                if filename.endswith(sds_common.SDS_JSON_FILE_EXTENSION):
                    file_path = os.path.abspath(os.path.join(rootdir, filename))
                    os.remove(file_path)

        for rootdir, dirnames, filenames in os.walk(src_path):
            for filename in filenames:
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                process_file(file_path, swift_bridging_path, args.intermediates)


# TODO: We can't access ivars from Swift without public property accessors.
# TODO: We can't access private properties from Swift without public property accessors.
#       We could generate "SDS Private" headers that exposes these properties, but only if they're backed by an ivar.
# TODO: Preprocessor macros & directives won't work properly with this AST parser.
