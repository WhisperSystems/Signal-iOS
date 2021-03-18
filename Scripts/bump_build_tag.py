#!/usr/bin/env python
from __future__ import print_function
import sys
import os
import re
import commands
import subprocess
import argparse
import inspect    

def fail(message):
    file_name = __file__
    current_line_no = inspect.stack()[1][2]
    current_function_name = inspect.stack()[1][3]
    print('Failure in:', file_name, current_line_no, current_function_name)
    print(message)
    sys.exit(1)


def execute_command(command):
    try:
        print(' '.join(command))
        output = subprocess.check_output(command)
        if output:
            print(output)
    except subprocess.CalledProcessError as e:
        print(e.output)
        sys.exit(1)


def find_project_root():
    path = os.path.abspath(os.curdir)
    
    while True:
        # print 'path', path
        if not os.path.exists(path):
            break
        git_path = os.path.join(path, '.git')
        if os.path.exists(git_path):
            return path
        new_path = os.path.abspath(os.path.dirname(path))
        if not new_path or new_path == path:
            break
        path = new_path
    
    fail('Could not find project root path')
        
        
def is_valid_release_version(value):
    regex = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')
    match = regex.search(value)
    return match is not None
        
        
def is_valid_build_version(value):
    regex = re.compile(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$')
    match = regex.search(value)
    return match is not None
        

def set_versions(plist_file_path, release_version, build_version):
    if not is_valid_release_version(release_version):
        fail('Invalid release version: %s' % release_version)
    if not is_valid_build_version(build_version):
        fail('Invalid build version: %s' % build_version)

    with open(plist_file_path, 'rt') as f:
        text = f.read()
    # print 'text', text

    # The "short" version is the release number.
    #
    # <key>CFBundleShortVersionString</key>
    # <string>2.20.0</string>
    file_regex = re.compile(r'<key>CFBundleShortVersionString</key>\s*<string>([\d\.]+)</string>', re.MULTILINE)
    file_match = file_regex.search(text)
    # print 'match', match
    if not file_match:   
        fail('Could not parse .plist')
    text = text[:file_match.start(1)] + release_version + text[file_match.end(1):]

    # The "long" version is the build number.
    #
    # <key>CFBundleVersion</key>
    # <string>2.20.0.3</string>
    file_regex = re.compile(r'<key>CFBundleVersion</key>\s*<string>([\d\.]+)</string>', re.MULTILINE)
    file_match = file_regex.search(text)
    # print 'match', match
    if not file_match:   
        fail('Could not parse .plist')
    text = text[:file_match.start(1)] + build_version + text[file_match.end(1):]
    
    with open(plist_file_path, 'wt') as f:
        f.write(text)
        
        
def get_versions(plist_file_path):
    with open(plist_file_path, 'rt') as f:
        text = f.read()
    # print 'text', text

    # <key>CFBundleVersion</key>
    # <string>2.13.0.13</string>
    file_regex = re.compile(r'<key>CFBundleVersion</key>\s*<string>([\d\.]+)</string>', re.MULTILINE)
    file_match = file_regex.search(text)
    # print 'match', match
    if not file_match:   
        fail('Could not parse .plist')
    
    # e.g. "2.13.0.13"
    old_build_version = file_match.group(1)
    print('old_build_version:', old_build_version)
    
    if not is_valid_build_version(old_build_version):
        fail('Invalid build version: %s' % old_build_version)
    
    build_number_regex = re.compile(r'\.(\d+)$')
    build_number_match = build_number_regex.search(old_build_version)
    if not build_number_match:   
        fail('Could not parse .plist version')
    
    # e.g. "13"
    old_build_number = build_number_match.group(1)
    print('old_build_number:', old_build_number)
    
    release_number_regex = re.compile(r'^(.+)\.\d+$')
    release_number_match = release_number_regex.search(old_build_version)
    if not release_number_match:   
        fail('Could not parse .plist')
    
    # e.g. "2.13.0"
    old_release_version = release_number_match.group(1)
    print('old_release_version:', old_release_version)
    
    # Given "2.13.0.13", this should return "2.13.0" and "13" as strings.
    return old_release_version, old_build_number
        
        
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Precommit cleanup script.')
    parser.add_argument('--version', help='used for starting a new version.')
    parser.add_argument('--internal', action='store_true', help='used to indicate throwaway builds.')

    args = parser.parse_args()

    is_internal = args.internal
    
    project_root_path = find_project_root()
    # print 'project_root_path', project_root_path
    # plist_path
    main_plist_path = os.path.join(project_root_path, 'Signal', 'Signal-Info.plist')
    if not os.path.exists(main_plist_path):
        fail('Could not find main app info .plist')

    sae_plist_path = os.path.join(project_root_path, 'SignalShareExtension', 'Info.plist')
    if not os.path.exists(sae_plist_path):
        fail('Could not find share extension info .plist')

    nse_plist_path = os.path.join(project_root_path, 'NotificationServiceExtension', 'Info.plist')
    if not os.path.exists(nse_plist_path):
        fail('Could not find NSE info .plist')
        
    output = subprocess.check_output(['git', 'status', '--porcelain'])
    if len(output.strip()) > 0:
        print(output)
        fail('Git repository has untracked files.')
    output = subprocess.check_output(['git', 'diff', '--shortstat'])
    if len(output.strip()) > 0:
        print(output)
        fail('Git repository has untracked files.')
    
    # Ensure .plist is in xml format, not binary.
    output = subprocess.check_output(['plutil', '-convert', 'xml1', main_plist_path])
    output = subprocess.check_output(['plutil', '-convert', 'xml1', sae_plist_path])
    output = subprocess.check_output(['plutil', '-convert', 'xml1', nse_plist_path])
    # print 'output', output
    
    # ---------------
    # Main App
    # ---------------

    old_release_version, old_build_number = get_versions(main_plist_path)

    if args.version:
        # e.g. --version 1.2.3 -> "1.2.3", "1.2.3.0"
        new_release_version = args.version.strip()
        new_build_version = new_release_version + ".0"
    else:
        new_build_number = str(1 + int(old_build_number))
        print('new_build_number:', new_build_number)
    
        new_release_version = old_release_version
        new_build_version = old_release_version + "." + new_build_number

    print('new_release_version:', new_release_version)
    print('new_build_version:', new_build_version)

    set_versions(main_plist_path, new_release_version, new_build_version)
    
    # ---------------
    # Share Extension
    # ---------------

    set_versions(sae_plist_path, new_release_version, new_build_version)
    
    # ------------------------------
    # Notification Service Extension
    # ------------------------------

    set_versions(nse_plist_path, new_release_version, new_build_version)
    
    # ---------------
    # Git
    # ---------------
    command = ['git', 'add', '.']
    execute_command(command)

    if is_internal:
        commit_message = '"Bump build to %s." (Internal)' % new_build_version
    else:
        commit_message = '"Bump build to %s."' % new_build_version
    command = ['git', 'commit', '-m', commit_message]
    execute_command(command)

    tag_name = new_build_version
    if is_internal:
        tag_name += "-internal"
    command = ['git', 'tag', tag_name]
    execute_command(command)
    
        
