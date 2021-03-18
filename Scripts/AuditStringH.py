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

git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())

string_h_functions = [
        "memchr",
        "memcmp",
        "memcpy",
        "memmove",
        "memset",
        "strcat",
        "strchr",
        "strcmp",
        "strcoll",
        "strcpy",
        "strcspn",
        "strerror",
        "strlen",
        "strncat",
        "strncmp",
        "strncpy",
        "strpbrk",
        "strrchr",
        "strspn",
        "strstr",
        "strtok",
        "strxfrm",
        "strtok_r",
        "strerror_r",
        "strdup",
        "memccpy",
        "stpcpy",
        "stpncpy",
        "strndup",
        "strnlen",
        "strsignal",
        "memset_s",
        "memmem",
        "memset_pattern4",
        "memset_pattern8",
        "memset_pattern16",
        "strcasestr",
        "strnstr",
        "strlcat",
        "strlcpy",
        "strmode",
        "strsep",
        "swab",
        "timingsafe_bcmp",
    ]


def process_if_appropriate(file_path):
    file_ext = os.path.splitext(file_path)[1]
    if file_ext.lower() not in ('.c', '.cpp', '.m', '.mm', '.h', '.swift'):
        return
    # print 'file_path', file_path, 'file_ext', file_ext
    
    with open(file_path, 'rt') as f:
        text = f.read()

    has_match = False
    for string_h_function in string_h_functions:
        regex = re.compile(string_h_function + r'\s*\(')
        assert(regex)
        matches = []
        for match in regex.finditer(text):
            matches.append(match)
        # matches = regex.findall(text)
        if not matches:
            continue
        if not has_match:
            has_match = True
            print('file_path', file_path, 'file_ext', file_ext)
        for match in matches:
            # print 'match', match, type(match)
            print('\t', 'match:', match.group(0))
    if has_match:
        print()
    
    
if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='Precommit script.')
    parser.add_argument('--path', help='used to specify a path to process.')
    args = parser.parse_args()
    
    
    if args.path:
        dir_path = args.path
    else:
        dir_path = git_repo_path

    for rootdir, dirnames, filenames in os.walk(dir_path):
        for filename in filenames:
            file_path = os.path.abspath(os.path.join(rootdir, filename))
            process_if_appropriate(file_path)
