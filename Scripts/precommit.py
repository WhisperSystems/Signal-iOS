#!/usr/bin/env python2.7
# -*- coding: utf-8 -*-

from __future__ import print_function
import os
import sys
import subprocess
import datetime
import argparse
import commands


git_repo_path = os.path.abspath(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).strip())



class include:
    def __init__(self, isInclude, isQuote, body, comment):
        self.isInclude = isInclude
        self.isQuote = isQuote
        self.body = body
        self.comment = comment

    def format(self):
        result = '%s %s%s%s' % (
                                ('#include' if self.isInclude else '#import'),
                                ('"' if self.isQuote else '<'),
                                self.body.strip(),
                                ('"' if self.isQuote else '>'),
                                )
        if self.comment.strip():
            result += ' ' + self.comment.strip()
        return result


def is_include_or_import(line):
    line = line.strip()
    if line.startswith('#include '):
        return True
    elif line.startswith('#import '):
        return True
    else:
        return False


def parse_include(line):
    remainder = line.strip()

    if remainder.startswith('#include '):
        isInclude = True
        remainder = remainder[len('#include '):]
    elif remainder.startswith('#import '):
        isInclude = False
        remainder = remainder[len('#import '):]
    elif remainder == '//':
        return None
    elif not remainder:
        return None
    else:
        print ('Unexpected import or include: '+ line)
        sys.exit(1)

    comment = None
    if remainder.startswith('"'):
        isQuote = True
        endIndex = remainder.find('"', 1)
        if endIndex < 0:
            print ('Unexpected import or include: '+ line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    elif remainder.startswith('<'):
        isQuote = False
        endIndex = remainder.find('>', 1)
        if endIndex < 0:
            print ('Unexpected import or include: '+ line)
            sys.exit(1)
        body = remainder[1:endIndex]
        comment = remainder[endIndex+1:]
    else:
        print ('Unexpected import or include: '+ remainder)
        sys.exit(1)

    return include(isInclude, isQuote, body, comment)


def parse_includes(text):
    lines = text.split('\n')

    includes = []
    for line in lines:
        include = parse_include(line)
        if include:
            includes.append(include)

    return includes


def sort_include_block(text, filepath, filename, file_extension):
    lines = text.split('\n')

    includes = parse_includes(text)

    blocks = []

    file_extension = file_extension.lower()

    for include in includes:
        include.isInclude = False

    if file_extension in ('c', 'cpp', 'hpp'):
        for include in includes:
            include.isInclude = True
    elif file_extension in ('m'):
        for include in includes:
            include.isInclude = False

    # Make sure matching header is first.
    matching_header_includes = []
    other_includes = []
    def is_matching_header(include):
        filename_wo_ext = os.path.splitext(filename)[0]
        include_filename_wo_ext = os.path.splitext(os.path.basename(include.body))[0]
        return filename_wo_ext == include_filename_wo_ext
    for include in includes:
        if is_matching_header(include):
            matching_header_includes.append(include)
        else:
            other_includes.append(include)
    includes = other_includes

    def formatBlock(includes):
        lines = [include.format() for include in includes]
        lines = list(set(lines))
        def include_sorter(a, b):
            # return cmp(a.lower(), b.lower())
            return cmp(a, b)
        # print 'before'
        # for line in lines:
        #     print '\t', line
        # print
        lines.sort(include_sorter)
        # print 'after'
        # for line in lines:
        #     print '\t', line
        # print
        # print
        # print 'filepath'
        # for line in lines:
        #     print '\t', line
        # print
        return '\n'.join(lines)

    includeAngles = [include for include in includes if include.isInclude and not include.isQuote]
    includeQuotes = [include for include in includes if include.isInclude and include.isQuote]
    importAngles = [include for include in includes if (not include.isInclude) and not include.isQuote]
    importQuotes = [include for include in includes if (not include.isInclude) and include.isQuote]
    if matching_header_includes:
        blocks.append(formatBlock(matching_header_includes))
    if includeQuotes:
        blocks.append(formatBlock(includeQuotes))
    if includeAngles:
        blocks.append(formatBlock(includeAngles))
    if importQuotes:
        blocks.append(formatBlock(importQuotes))
    if importAngles:
        blocks.append(formatBlock(importAngles))

    return '\n'.join(blocks) + '\n'


def sort_class_statement_block(text, filepath, filename, file_extension):
    lines = text.split('\n')
    lines = [line.strip() for line in lines if line.strip()]
    lines = list(set(lines))
    lines.sort()
    return '\n' + '\n'.join(lines) + '\n'


def find_matching_section(text, match_test):
    lines = text.split('\n')
    first_matching_line_index = None
    for index, line in enumerate(lines):
        if match_test(line):
            first_matching_line_index = index
            break

    if first_matching_line_index is None:
        return None

    # Absorb any leading empty lines.
    while first_matching_line_index > 0:
        prev_line = lines[first_matching_line_index - 1]
        if prev_line.strip():
            break
        first_matching_line_index = first_matching_line_index - 1

    first_non_matching_line_index = None
    for index, line in enumerate(lines[first_matching_line_index:]):
        if not line.strip():
            # Absorb any trailing empty lines.
            continue
        if not match_test(line):
            first_non_matching_line_index = index + first_matching_line_index
            break

    text0 = '\n'.join(lines[:first_matching_line_index])
    if first_non_matching_line_index is None:
        text1 = '\n'.join(lines[first_matching_line_index:])
        text2 = None
    else:
        text1 = '\n'.join(lines[first_matching_line_index:first_non_matching_line_index])
        text2 = '\n'.join(lines[first_non_matching_line_index:])

    return text0, text1, text2


def sort_matching_blocks(sort_name, filepath, filename, file_extension, text, match_func, sort_func):
    unprocessed = text
    processed = None
    while True:
        section = find_matching_section(unprocessed, match_func)
        # print '\t', 'sort_matching_blocks', section
        if not section:
            if processed:
                processed = '\n'.join((processed, unprocessed,))
            else:
                processed = unprocessed
            break

        text0, text1, text2 = section

        if processed:
            processed = '\n'.join((processed, text0,))
        else:
            processed = text0

        # print 'before:'
        # temp_lines = text1.split('\n')
        # for index, line in enumerate(temp_lines):
        #     if index < 3 or index + 3 >= len(temp_lines):
        #         print '\t', index, line
        # # print text1
        # print
        text1 = sort_func(text1, filepath, filename, file_extension)
        # print 'after:'
        # # print text1
        # temp_lines = text1.split('\n')
        # for index, line in enumerate(temp_lines):
        #     if index < 3 or index + 3 >= len(temp_lines):
        #         print '\t', index, line
        # print
        processed = '\n'.join((processed, text1,))
        if text2:
            unprocessed = text2
        else:
            break

    if text != processed:
        print(sort_name, filepath)
    return processed


def find_class_statement_section(text):
    def is_class_statement(line):
        return line.strip().startswith('@class ')

    return find_matching_section(text, is_class_statement)


def find_include_section(text):
    def is_include_line(line):
        return is_include_or_import(line)
        # return is_include_or_import_or_empty(line)

    return find_matching_section(text, is_include_line)


def sort_includes(filepath, filename, file_extension, text):
    # print 'sort_includes', filepath
    if file_extension not in ('.h', '.m', '.mm'):
        return text
    return sort_matching_blocks('sort_includes', filepath, filename, file_extension, text, find_include_section, sort_include_block)


def sort_class_statements(filepath, filename, file_extension, text):
    # print 'sort_class_statements', filepath
    if file_extension not in ('.h', '.m', '.mm'):
        return text
    return sort_matching_blocks('sort_class_statements', filepath, filename, file_extension, text, find_class_statement_section, sort_class_statement_block)


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


def process(filepath):

    short_filepath = filepath[len(git_repo_path):]
    if short_filepath.startswith(os.sep):
       short_filepath = short_filepath[len(os.sep):]

    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        raise "shouldn't call process with dotfile"
    file_ext = os.path.splitext(filename)[1]
    if file_ext in ('.swift'):
        env_copy = os.environ.copy()
        env_copy["SCRIPT_INPUT_FILE_COUNT"] = "1"
        env_copy["SCRIPT_INPUT_FILE_0"] = '%s' % ( short_filepath, )
        lint_output = subprocess.check_output(['swiftlint', 'autocorrect', '--use-script-input-files'], env=env_copy)
        print(lint_output)
        try:
            lint_output = subprocess.check_output(['swiftlint', 'lint', '--use-script-input-files'], env=env_copy)
        except subprocess.CalledProcessError as e:
            lint_output = e.output
        print(lint_output)

    with open(filepath, 'rt') as f:
        text = f.read()

    original_text = text

    text = sort_includes(filepath, filename, file_ext, text)
    text = sort_class_statements(filepath, filename, file_ext, text)

    lines = text.split('\n')
    while lines and lines[0].startswith('//'):
        lines = lines[1:]
    text = '\n'.join(lines)
    text = text.strip()

    header = '''//
//  Copyright (c) %s Open Whisper Systems. All rights reserved.
//

''' % (
    datetime.datetime.now().year,
    )
    text = header + text + '\n'

    if original_text == text:
        return

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
        if component in ('Pods', 'ThirdParty', 'Carthage',):
            return True

    return False


def process_if_appropriate(filepath):
    filename = os.path.basename(filepath)
    if filename.startswith('.'):
        return
    file_ext = os.path.splitext(filename)[1]
    if file_ext not in ('.h', '.hpp', '.cpp', '.m', '.mm', '.pch', '.swift'):
        return
    if should_ignore_path(filepath):
        return
    process(filepath)


def check_diff_for_keywords():
    objc_keywords = [
        "OWSAbstractMethod\(",
        "OWSAssert\(",
        "OWSCAssert\(",
        "OWSFail\(",
        "OWSCFail\(",
        "ows_add_overflow\(",
        "ows_sub_overflow\(",
    ]

    swift_keywords = [
        "owsFail\(",
        "precondition\(",
        "fatalError\(",
        "dispatchPrecondition\(",
        "preconditionFailure\(",
        "notImplemented\("
    ]

    keywords = objc_keywords + swift_keywords

    matching_expression = "|".join(keywords)
    command_line = 'git diff --staged | grep --color=always -C 3 -E "%s"' % matching_expression
    try:
        output = subprocess.check_output(command_line, shell=True)
    except subprocess.CalledProcessError as e:
        # > man grep
        #  EXIT STATUS
        #  The grep utility exits with one of the following values:
        #  0     One or more lines were selected.
        #  1     No lines were selected.
        #  >1    An error occurred.
        if e.returncode == 1:
            # no keywords in diff output
            return
        else:
            # some other error - bad grep expression?
            raise e

    if len(output) > 0:
        print("⚠️  keywords detected in diff:")
        print(output)

if __name__ == "__main__":

    parser = argparse.ArgumentParser(description='Precommit script.')
    parser.add_argument('--all', action='store_true', help='process all files in or below current dir')
    parser.add_argument('--path', help='used to specify a path to process.')
    parser.add_argument('--ref', help='process all files that have changed since the given ref')
    args = parser.parse_args()

    clang_format_commit = 'HEAD'

    if args.all:
        for rootdir, dirnames, filenames in os.walk(git_repo_path):
            for filename in filenames:
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                process_if_appropriate(file_path)
    elif args.path:
        for rootdir, dirnames, filenames in os.walk(args.path):
            for filename in filenames:
                file_path = os.path.abspath(os.path.join(rootdir, filename))
                process_if_appropriate(file_path)
    elif args.ref:
        filepaths = []

        output = commands.getoutput('git diff --name-only --diff-filter=ACMR HEAD %s' % args.ref)
        filepaths.extend([line.strip() for line in output.split('\n')])

        # Only process each path once.
        filepaths = sorted(set(filepaths))

        for filepath in filepaths:
            filepath = os.path.abspath(os.path.join(git_repo_path, filepath))
            if os.path.exists(filepath):
                process_if_appropriate(filepath)

        clang_format_commit = args.ref
    else:
        filepaths = []

        # Staging
        output = commands.getoutput('git diff --cached --name-only --diff-filter=ACMR')
        filepaths.extend([line.strip() for line in output.split('\n')])

        # Working
        output = commands.getoutput('git diff --name-only --diff-filter=ACMR')
        filepaths.extend([line.strip() for line in output.split('\n')])

        # Only process each path once.
        filepaths = sorted(set(filepaths))

        for filepath in filepaths:
            filepath = os.path.abspath(os.path.join(git_repo_path, filepath))
            process_if_appropriate(filepath)

    print('git clang-format...')
    # we don't want to format .proto files, so we specify every other supported extension
    print(commands.getoutput('git clang-format --extensions "c,h,m,mm,cc,cp,cpp,c++,cxx,hh,hxx,cu,java,js,ts,cs" --commit %s' % clang_format_commit))

    check_diff_for_keywords()
