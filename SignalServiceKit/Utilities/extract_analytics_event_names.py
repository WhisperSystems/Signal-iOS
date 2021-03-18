#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function
import os
import sys
import subprocess 
import datetime
import argparse
import commands
import re


# This script is used to extract analytics event names from the codebase,
# and convert them to constants in OWSAnalyticsEvents.

git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())


def splitall(path):
    allparts = []
    while 1:
        parts = os.path.split(path)
        if parts[0] == path:  # sentinel for absolute paths
            allparts.insert(0, parts[0])
            break
        elif parts[1] == path: # sentinel for relative paths
            allparts.insert(0, parts[1])
            break
        else:
            path = parts[0]
            allparts.insert(0, parts[1])
    return allparts


def objc_name_for_event_name(event_name):
    while True:
        index = event_name.find('_')
        if index < 0:
            break
        if index >= len(event_name) - 1:
            break
        nextChar = event_name[index + 1]
        event_name = event_name[:index] + nextChar.upper() + event_name[index + 2:]
    return event_name


event_names = []
    
def process(filepath, c_macros, swift_macros):

    short_filepath = filepath[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):] 
    
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    if filename == 'OWSAnalytics.h':
        return
    file_ext = os.path.splitext(filename)[1]
    
    is_swift = file_ext in ('.swift')
    
    
    if is_swift:
        macros = swift_macros
    else:
        macros = c_macros
    
    # print short_filepath, is_swift
    
    with open(filepath, 'rt') as f:
        text = f.read()
    
    replacement_map = {}
    
    position = 0
    has_printed_filename = False
    while True:
        best_match = None
        best_macro = None
        for macro in macros:
            pattern = r'''%s\(([^,\)]+)[,\)]''' % macro
            # print '\t pattern', pattern
            matcher = re.compile(pattern)
            # matcher = re.compile(r'#define (OWSProd)')
            match = matcher.search(text, pos=position)
            if match:
                event_name = match.group(1).strip()
                
                # Ignore swift func definitions
                if is_swift and ':' in event_name:
                    continue
                    
                # print '\t', 'event_name', event_name
                
                if not best_match:
                    pass
                elif best_match.start(1) > match.start(1):
                    pass
                else:
                    continue

                best_match = match
                best_macro = macro
        # TODO:
        if not best_match:
            break
            
        position = best_match.end(1)
        if not has_printed_filename:
            has_printed_filename = True
            print(short_filepath)
        
        raw_event_name = best_match.group(1).strip()
        if is_swift:
            pattern = r'^"(.+)"$'
        else:
            pattern = r'^@"(.+)"$'
        # print 'pattern:', pattern
        matcher = re.compile(pattern)
        # matcher = re.compile(r'#define (OWSProd)')
        match = matcher.search(raw_event_name)
        if match:
            event_name = match.group(1).strip()
        else:
            print('\t', 'Ignoring event: _%s_' % raw_event_name)
            continue
        event_names.append(event_name)
        print('\t', 'event_name', event_name)
        
        if is_swift:
            before = '"%s"' % event_name
            after = 'OWSAnalyticsEvents.%s()' % objc_name_for_event_name(event_name)
        else:
            before = '@"%s"' % event_name
            after = '[OWSAnalyticsEvents %s]' % objc_name_for_event_name(event_name)
        replacement_map[before] = after
                
        # macros.append(macro)
        
        # break
    
    # print 'replacement_map', replacement_map
    
    for before in replacement_map:
        after = replacement_map[before]
        text = text.replace(before, after)

    # if original_text == text:
    #     return
    
    print('Updating:', short_filepath)
    
    with open(filepath, 'wt') as f:
        f.write(text)


def should_ignore_path(path):
    ignore_paths = [
        os.path.join(git_repo_path, '.git')
    ]
    for ignore_path in ignore_paths:
        if path.startswith(ignore_path):
            return True
    for component in splitall(path):
        if component.startswith('.'):
            return True
        if component.endswith('.framework'):
            return True
        if component in ('Pods', 'ThirdParty',):
            return True                
        
    return False
    
    
def process_if_appropriate(filepath, c_macros, swift_macros):
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    file_ext = os.path.splitext(filename)[1]
    if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch', '.swift'):
        return
    if should_ignore_path(filepath):
        return
    process(filepath, c_macros, swift_macros)

    
def extract_macros(filepath):

    filename = os.path.basename(filepath)
    file_ext = os.path.splitext(filename)[1]
    is_swift = file_ext in ('.swift')

    macros = []
    
    with open(filepath, 'rt') as f:
        text = f.read()
    
    lines = text.split('\n')
    for line in lines:
        # Match lines of this form: 
        # #define OWSProdCritical(__eventName) ...
    
        if is_swift:
            matcher = re.compile(r'func (OWSProd[^\(]+)\(.+[,\)]')
        else:
            matcher = re.compile(r'#define (OWSProd[^\(]+)\(.+[,\)]')
        # matcher = re.compile(r'#define (OWSProd)')
        match = matcher.search(line)
        if match:
            macro = match.group(1).strip()
            # print 'macro', macro
            macros.append(macro)
    
    return macros
    
    
def update_event_names(header_file_path, source_file_path):
    # global event_names
    # event_names = sorted(set(event_names))
    code_generation_marker = '#pragma mark - Code Generation Marker'
    
    # Source
    filepath = source_file_path
    with open(filepath, 'rt') as f:
        text = f.read()
    
    code_generation_start = text.find(code_generation_marker)
    code_generation_end = text.rfind(code_generation_marker)
    if code_generation_start < 0:
        print('Could not find marker in file:', file)
        sys.exit(1)
    if code_generation_end < 0 or code_generation_end == code_generation_start:
        print('Could not find marker in file:', file)
        sys.exit(1)

    event_name_map = {}

    print()
    print('Parsing old generated code')
    print()

    old_generated = text[code_generation_start + len(code_generation_marker):code_generation_end]
    # print 'old_generated', old_generated
    for split in old_generated.split('+'):
        split = split.strip()
        # print 'split:', split
        if not split:
            continue
        
        # Example:
        #(NSString *)call_service_call_already_set
        #{
        #    return @"call_service_call_already_set";
        #}        
        
        pattern = r'\(NSString \*\)([^\s\r\n\t]+)[\s\r\n\t]'
        matcher = re.compile(pattern)
        match = matcher.search(split)
        if not match:
            print('Could not parse:', split)
            print('In file:', filepath)
            sys.exit(1)

        method_name = match.group(1).strip()
        print('method_name:', method_name)
        
        pattern = r'return @"(.+)";'
        matcher = re.compile(pattern)
        match = matcher.search(split)
        if not match:
            print('Could not parse:', split)
            print('In file:', filepath)
            sys.exit(1)

        event_name = match.group(1).strip()
        print('event_name:', event_name)
        
        event_name_map[event_name] = method_name
    
    print()
    
    
    all_event_names = sorted(set(event_name_map.keys() + event_names))
    print('all_event_names', all_event_names)
        
    generated = code_generation_marker
    for event_name in all_event_names:
        # Example:
        # + (NSString *)call_service_call_already_set;
        if event_name in event_name_map:
            objc_name = event_name_map[event_name]
        else:
            objc_name = objc_name_for_event_name(event_name)
        text_for_event = '''+ (NSString *)%s
{
    return @"%s";
}''' % (objc_name, event_name)
        generated = generated + '\n\n' + text_for_event
    generated = generated + '\n\n' + code_generation_marker
    print('generated', generated)
    new_text = text[:code_generation_start] + generated + text[code_generation_end + len(code_generation_marker):]
    print('text', new_text)
    with open(filepath, 'wt') as f:
        f.write(new_text)

    
    # Header
    filepath = header_file_path
    with open(filepath, 'rt') as f:
        text = f.read()
    
    code_generation_start = text.find(code_generation_marker)
    code_generation_end = text.rfind(code_generation_marker)
    if code_generation_start < 0:
        print('Could not find marker in file:', file)
        sys.exit(1)
    if code_generation_end < 0 or code_generation_end == code_generation_start:
        print('Could not find marker in file:', file)
        sys.exit(1)
    
    generated = code_generation_marker
    for event_name in all_event_names:
        # Example:
        # + (NSString *)call_service_call_already_set;
        objc_name = objc_name_for_event_name(event_name)
        text_for_event = '+ (NSString *)%s;' % (objc_name,)
        generated = generated + '\n\n' + text_for_event
    generated = generated + '\n\n' + code_generation_marker
    print('generated', generated)
    new_text = text[:code_generation_start] + generated + text[code_generation_end + len(code_generation_marker):]
    print('text', new_text)
    with open(filepath, 'wt') as f:
        f.write(new_text)
    
    
    
if __name__ == "__main__":
    # print 'git_repo_path', git_repo_path
    
    macros_header_file_path = os.path.join(git_repo_path, 'SignalServiceKit', 'src', 'Util', 'OWSAnalytics.h')
    if not os.path.exists(macros_header_file_path):
        print('Macros header does not exist:', macros_header_file_path)
        sys.exit(1)
    c_macros = extract_macros(macros_header_file_path)
    print('c_macros:', c_macros)

    macros_header_file_path = os.path.join(git_repo_path, 'Signal', 'src', 'util', 'OWSAnalytics.swift')
    if not os.path.exists(macros_header_file_path):
        print('Macros header does not exist:', macros_header_file_path)
        sys.exit(1)
    swift_macros = extract_macros(macros_header_file_path)
    print('swift_macros:', swift_macros)

    event_names_header_file_path = os.path.join(git_repo_path, 'SignalServiceKit', 'src', 'Util', 'OWSAnalyticsEvents.h')
    if not os.path.exists(event_names_header_file_path):
        print('event_names_header_file_path does not exist:', event_names_header_file_path)
        sys.exit(1)

    event_names_source_file_path = os.path.join(git_repo_path, 'SignalServiceKit', 'src', 'Util', 'OWSAnalyticsEvents.m')
    if not os.path.exists(event_names_source_file_path):
        print('event_names_source_file_path does not exist:', event_names_source_file_path)
        sys.exit(1)
        
    for rootdir, dirnames, filenames in os.walk(git_repo_path):
        for filename in filenames:
            file_path = os.path.abspath(os.path.join(rootdir, filename))
            process_if_appropriate(file_path, c_macros, swift_macros)

    print()
    print('event_names', sorted(set(event_names)))
    update_event_names(event_names_header_file_path, event_names_source_file_path)
