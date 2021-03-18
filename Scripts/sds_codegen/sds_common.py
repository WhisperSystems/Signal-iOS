#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

from __future__ import print_function
import os
import subprocess

SDS_JSON_FILE_EXTENSION = '.sdsjson'

def fail(*args):
    error = ' '.join(str(arg) for arg in args)
    raise Exception(error)


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())
print('git_repo_path:', git_repo_path)

def sds_to_relative_path(path):
    path = os.path.abspath(path)
    if not path.startswith(git_repo_path):
        fail('Unexpected path:', path)
    path = path[len(git_repo_path):]
    if path.startswith(os.sep):
        path = path[len(os.sep):]
    return path


def sds_from_relative_path(path):
    return os.path.join(git_repo_path, path)


def clean_up_generated_code(text):
    # Remove trailing whitespace.
    lines = text.split('\n')
    lines = [line.rstrip() for line in lines]
    text = '\n'.join(lines)
    # Compact newlines.
    while '\n\n\n' in text:
        text = text.replace('\n\n\n', '\n\n')
    # Ensure there's a trailing newline.
    return text.strip() + '\n'


def clean_up_generated_swift(text):
    return clean_up_generated_code(text)


def clean_up_generated_objc(text):
    return clean_up_generated_code(text)


def pretty_module_path(path):
    path = os.path.abspath(path)
    if path.startswith(git_repo_path):
       path = path[len(git_repo_path):]
    return path

def write_text_file_if_changed(file_path, text):
    if os.path.exists(file_path):
        with open(file_path, 'rt') as f:
            oldText = f.read()
            if oldText == text:
                return

    with open(file_path, 'wt') as f:
        f.write(text)
