#!/usr/bin/env python
from __future__ import print_function
import sys
import os
import re
import commands
import subprocess
import argparse
import inspect    
import urllib2
import json

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

def add_field(curl_command, form_key, form_value):
    curl_command.append('-F')
    curl_command.append("%s=%s" % (form_key, form_value))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Precommit cleanup script.')
    parser.add_argument('--file', required=True, help='used for starting a new version.')

    args = parser.parse_args()
    
    params_response = urllib2.urlopen("https://debuglogs.org/").read()
    
    params = json.loads(params_response)
    
    upload_url = params['url']
    upload_fields = params['fields']

    upload_key = upload_fields.pop('key')
    upload_key = upload_key + os.path.splitext(args.file)[1]
    
    download_url = 'https://debuglogs.org/' + upload_key
    print('download_url:', download_url)
    
    curl_command = ['curl', '-v', '-i', '-X', 'POST']

    # key must appear before other fields
    add_field(curl_command, 'key', upload_key)
    for field_name in upload_fields:
        add_field(curl_command, field_name, upload_fields[field_name])

    add_field(curl_command, "content-type", "application/octet-stream")
 
    curl_command.append('-F')
    curl_command.append("file=@%s" % (args.file,))
    curl_command.append(upload_url)
    
    print(' '.join(curl_command))

    print('Running...')
    execute_command(curl_command)

    print('download_url:', download_url)
    
