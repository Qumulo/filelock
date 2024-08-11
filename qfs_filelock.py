#!/usr/bin/python3
################################################################################
#
# Copyright (c) 2024 Qumulo, Inc. All rights reserved.
#
# NOTICE: All information and intellectual property contained herein is the
# confidential property of Qumulo, Inc. Reproduction or dissemination of the
# information or intellectual property contained herein is strictly forbidden,
# unless separate prior written permission has been obtained from Qumulo, Inc.
#
# Name:     qfs_filelock.py
# Date:     2024-08-16
# Author:   kmac@qumulo.com
#
# Description:
# - This script monitors a specified directory or file on a Qumulo cluster for 
#   changes, such as file additions or ACL modifications, using the Qumulo API.
# - When a change is detected, the script attempts to apply a Write Once Read 
#   Many (WORM) lock to the affected file. This is achieved by setting a file 
#   lock with a specified retention period.
# - The script can operate in a recursive mode to monitor all subdirectories.
# - Debug mode is available for detailed logging, and the script supports 
#   configurable polling intervals.
#
# Usage:
# - The script can be run with command-line arguments specifying the file ID 
#   or directory path to monitor, as well as optional settings like debug mode 
#   and polling interval.
# - Configuration for connecting to the Qumulo API is provided via a configuration 
#   file.
#
################################################################################

import argparse
import configparser
import json
import logging
import os
import re
import requests
import sys
import time
import urllib3
import warnings
from datetime import datetime, timedelta
from urllib3.exceptions import InsecureRequestWarning

from qumulo.rest_client import RestClient
import qumulo.rest.fs as fs

interval = None

warnings.simplefilter('ignore', InsecureRequestWarning)

################################################################################
# function load_config - Load configuration from a file
################################################################################
def load_config(config_file):
    config = configparser.ConfigParser()
    config.read(config_file)
    if 'DEFAULT' not in config:
        raise ValueError(f"Configuration file {config_file} is missing the DEFAULT section.")
    return config

################################################################################
# function setup_logging - Set up logging configuration
################################################################################
def setup_logging(debug):
    level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(level=level, format='%(asctime)s - %(levelname)s - %(message)s')
    if not debug:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    else:
        warnings.simplefilter('ignore', InsecureRequestWarning)

################################################################################
# function debug_print - Print debug messages if debug mode is enabled
################################################################################
def debug_print(message, debug):
    if debug:
        logging.debug(message)

################################################################################
# function parse_args - Parse command line arguments
################################################################################
def parse_args():
    parser = argparse.ArgumentParser(description='Process Qumulo notifications.')
    parser.add_argument('--file-id', type=str, help='The file ID to monitor for changes')
    parser.add_argument('--directory-path', type=str, help='The directory path to monitor for changes')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--config-file', type=str, default='qfs_filelock_config.ini', help='Path to the configuration file')
    parser.add_argument('--interval', type=int, default=15, help='Interval for polling notifications')
    parser.add_argument('--output', type=str, help='Output file to save notifications')
    parser.add_argument('--recursive', action='store_true', help='Monitor directories recursively')
    args = parser.parse_args()
    if not args.file_id and not args.directory_path:
        parser.error('No action requested, add --file-id or --directory-path')
    return args

################################################################################
# function display_header - Display a header
################################################################################

def display_header(args, file_id=None, full_path=None):
    time_str = datetime.now().strftime("%Y-%m-%d %H:%M")
    width = 65
    border = '#'

    attributes = {
        "directory_path": "Directory:",
        "file_id": "File ID:",
        "interval": "Polling Interval:",
        "recursive": "Recursive:",
        "config_file": "Config File:",
        "output": "Output File:"
    }

    values = {
        "directory_path": full_path or getattr(args, 'directory_path', None),
        "file_id": file_id or getattr(args, 'file_id', None),
        "interval": args.interval,
        "recursive": args.recursive,
        "config_file": args.config_file,
        "output": args.output
    }

    max_label_length = max(len(label) for label in attributes.values())

    header = [
        f"{border * width}",
        f"{border}{'QFS File Lock Script'.center(width - 2)}{border}",
        f"{border}{time_str.center(width - 2)}{border}",
        f"{border * width}"
    ]

    for attr, label in attributes.items():
        value = values[attr]
        if value:
            if attr == "interval":
                value = f"{value} secs"
            header.append(f'{border} {label}{" " * (max_label_length - len(label) + 1)}{str(value).ljust(width - max_label_length - 4)}{border}')

    header.append(f"{border * width}")
    for line in header:
        print(line)

################################################################################
# function lock_file - Lock a file using Qumulo API's set_file_lock method
################################################################################
def lock_file(rc, args, full_path, file_id, debug):
    if not os.path.isabs(full_path):
        logging.error(f"Provided path is not absolute: {full_path}")
        return

    full_path = re.sub(r'/+', '/', full_path)
    retention_period = (datetime.utcnow() + timedelta(days=1)).replace(microsecond=0).isoformat() + 'Z'
    logging.debug(f"Attempting to lock the file: {full_path} with retention period: {retention_period}")

    max_retries = 3
    attempt = 0

    while attempt < max_retries:
        try:
            config = load_config(args.config_file)
            api_host = config['DEFAULT']['API_HOST']
            api_port = config['DEFAULT']['API_PORT']
            username = config['DEFAULT']['USERNAME']
            password = config['DEFAULT']['PASSWORD']

            rc = RestClient(api_host, api_port)
            rc.login(username, password)

            response = fs.set_file_lock(
                conninfo=rc.conninfo,
                _credentials=rc.credentials,
                path=full_path,
                retention_period=retention_period,
                legal_hold=False
            )
            logging.info(f"Successfully locked file: {full_path}")
            logging.debug(f"Response: {response}")
            break  

        except requests.exceptions.RequestException as e:
            attempt += 1
            logging.error(f"Failed to lock file: {full_path}, Error: {str(e)}, Attempt: {attempt}")
            logging.debug(f"Request Exception: {str(e)}")
            time.sleep(2) 
        except Exception as e:
            logging.error(f"Unexpected error when locking file: {full_path}, Error: {str(e)}")
            break 
    if attempt == max_retries:
        logging.error(f"Max retries reached. Failed to lock file: {full_path}")

################################################################################
# function get_fileinfo - Get file_id and fully qualified path
################################################################################
def get_fileinfo(rc, file_id=None, directory_path=None, debug=False):
    try:
        if file_id:
            response = fs.get_file_attr(rc.conninfo, rc.credentials, id_=file_id)
            if isinstance(response, tuple):
                response = response[0] 
            absolute_path = response['path']
        elif directory_path:
            response = fs.get_file_attr(rc.conninfo, rc.credentials, path=directory_path)
            if isinstance(response, tuple):
                response = response[0] 
            file_id = response['id']
            absolute_path = response['path']            
        else:
            raise ValueError("GFI: Either file_id or directory_path must be provided")
        
        return file_id, absolute_path

    except ValueError as ve:
        logging.error(f"Error in get_fileinfo: {ve}")
        return "Error_ID", "Error_Path"

    except requests.exceptions.RequestException as re:
        logging.error(f"Request Exception in get_fileinfo: {re}")
        return "Error_ID", "Error_Path"

################################################################################
# function stream_notifications - Stream notifications from Qumulo API
################################################################################

def stream_notifications(rc, args, debug=False, output_file=None):
    notification_types_to_handle = [
        "child_file_added",
        "child_acl_changed",
        "child_extra_attrs_changed"
    ]

    if args.file_id:
        file_id, full_path = get_fileinfo(rc, file_id=args.file_id, directory_path=args.directory_path, debug=debug)
        path = None
        id_ = file_id
    elif args.directory_path:
        file_id, full_path = get_fileinfo(rc, file_id=args.file_id, directory_path=args.directory_path, debug=debug)
        path = full_path
        id_ = None
    else:
        raise ValueError("Either file_id or directory_path must be provided")

    changes_iterator = fs.get_change_notify_listener(
        conninfo=rc.conninfo,
        _credentials=rc.credentials,
        recursive=args.recursive,
        type_filter=notification_types_to_handle,
        path=path,
        id_=id_,
    ).data

    debug_print(f"Listening for change notifications with ID: {file_id} or Path: {path}", debug)

    for change in changes_iterator:
        logging.debug(f"Received change object: {change}")

        if isinstance(change, list):
            for change_dict in change:
                change_type = change_dict.get('type')
                change_path = change_dict.get('path')

                if change_type:
                    logging.debug(f"Detected change of type: {change_type} at path: {change_path}")

                if change_type in notification_types_to_handle:
                    new_file_abs_path = (str(full_path) + '/' + str(change_path)).replace('//', '/')
                    logging.info(f"Received {change_type} notification for {new_file_abs_path} ")
                    print(f"Pausing for {interval} seconds before locking the file...", end='', flush=True)
                    for _ in range(interval):
                        time.sleep(1)
                        print('.', end='', flush=True) 
                    print()
                    lock_file(rc, args, new_file_abs_path, file_id, debug)
                    message = f"Waiting for notifications..."

                    if output_file:
                        with open(output_file, 'a') as f:
                            f.write(f"{datetime.now()} - {message}\n")
                    else:
                        logging.info(message)
                else:
                    logging.debug(f"Ignored change of type: {change_type} at path: {change_path}")
        else:
            logging.warning(f"Unexpected change format: {change}")

################################################################################
# Main function to process Qumulo notifications
################################################################################

def main():
    args = parse_args()
    global interval
    setup_logging(args.debug)
    
    if not os.path.exists(args.config_file):
        logging.error(f"Configuration file {args.config_file} does not exist.")
        print(f"Error: Configuration file {args.config_file} not found.\n")        
        sys.exit(1) 
    
    try:
        config = load_config(args.config_file)
        api_host = config['DEFAULT']['API_HOST']
        api_port = config['DEFAULT']['API_PORT']
        username = config['DEFAULT']['USERNAME']
        password = config['DEFAULT']['PASSWORD']
        interval = args.interval if args.interval is not None else 15
    except ValueError as ve:
        logging.error(f"Error loading configuration file: {ve}")
        return
    try:
        rc = RestClient(api_host, api_port)
        rc.login(username, password)

        if args.file_id or args.directory_path:
            file_id, full_path = get_fileinfo(rc, file_id=args.file_id, directory_path=args.directory_path, debug=args.debug)
            display_header(args, file_id, full_path)
        else:
            raise ValueError("Either file_id or directory_path must be provided")
    except ValueError as ve:
        logging.error(f"Setup Error: {ve}")
        return
    
    try:
        logging.info('Listening for change notifications...')
        stream_notifications(rc, args, debug=args.debug, output_file=args.output)
    except requests.exceptions.RequestException as e:
        logging.error(f'HTTP Request Error: {e}')
    except ValueError as ve:
        logging.error(f'Error: {ve}')

if __name__ == '__main__':
    main()

