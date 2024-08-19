#!/usr/bin/env python3

import os
import random
import concurrent.futures
from pathlib import Path

BASE_DIR = Path("/mnt/test/vault/deep")
MAX_DEPTH = 3
MIN_FILES = 1
MAX_FILES = 1000
MIN_SIZE = 1
MAX_SIZE = 5 * 1024

def create_single_file(filename):
    if filename.exists():
        print(f"Skipped: {filename} already exists.")
        return 0  # Skip the file if it already exists
    try:
        filesize_kb = random.randint(MIN_SIZE, MAX_SIZE)
        with open(filename, 'wb') as f:
            f.write(os.urandom(filesize_kb * 1024))
        print(f"Created: {filename}")
        return filesize_kb
    except OSError as e:
        print(f"Failed to create {filename}: {e}")  # Log the error for visibility
        return 0  # Return 0 if file creation fails due to OSError

def create_random_files(directory):
    num_files = random.randint(MIN_FILES, MAX_FILES)
    print(f"Creating {num_files} files in directory: {directory}")
    total_size = 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(create_single_file, directory / f"file_{i}.bin") for i in range(1, num_files + 1)]

        for future in concurrent.futures.as_completed(futures):
            try:
                total_size += future.result()
            except Exception as e:
                print(f"Failed to process a file: {e}")  # Handle any exception during file processing

    print(f"Finished creating files in directory: {directory}, Total size: {total_size // 1024} MiB")
    return total_size

def create_directories_and_files(current_depth, current_dir):
    if current_depth < MAX_DEPTH:
        num_subdirs = random.randint(1, 3)
        subdirs = []
        for i in range(num_subdirs):
            subdir = current_dir / f"dir_{current_depth}_{i}"
            try:
                subdir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                print(f"Failed to create directory {subdir}: {e}")  # Handle directory creation errors
            subdirs.append(subdir)

        for subdir in subdirs:
            create_directories_and_files(current_depth + 1, subdir)

    create_random_files(current_dir)

if __name__ == "__main__":
    try:
        BASE_DIR.mkdir(parents=True, exist_ok=True)
        create_directories_and_files(1, BASE_DIR)
    except Exception as e:
        print(f"Failed during execution: {e}")  # Handle any general exceptions