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


def process_file(file_path):
    print('Scanning:', file_path)

    with open(file_path, 'rt') as f:
        src_text = f.read()

    regex = re.compile(r'(@import (.+);)')

    text = src_text
    while True:
        match = regex.search(text)
        if match is None:
            break

        import_name = match.group(2)
        if import_name == 'Compression':
            # Ignore this framework.
            continue

        print('\t', 'Fixing:', import_name)
        new_import = '#import <%s/%s.h>' % ( import_name, import_name, )
        text = text[:match.start(1)] + new_import + text[match.end(1):]

    if text == src_text:
        return


    with open(file_path, 'wt') as f:
        f.write(text)


# ---

def search_path(module_name):
    dir_path = os.path.abspath(os.path.join(git_repo_path, module_name))
    for rootdir, dirnames, filenames in os.walk(dir_path):
        for filename in filenames:
            if not (filename.endswith('.h') or filename.endswith('.m') or filename.endswith('.pch')):
                continue
            file_path = os.path.abspath(os.path.join(rootdir, filename))
            process_file(file_path)


# ---

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Parse Objective-C AST.')
    args = parser.parse_args()

    search_path('Signal')
    search_path('SignalMessaging')
    search_path('SignalServiceKit')
