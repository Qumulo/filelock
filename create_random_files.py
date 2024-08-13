#!/usr/bin/env python3

import os
import random
import concurrent.futures
from pathlib import Path

BASE_DIR = Path("/mnt/test/vault/deep")
MAX_DEPTH = 2  # Reduced depth to 2
MIN_FILES = 1
MAX_FILES = 100  # Reduced number for performance
MIN_SIZE = 1       # Minimum size in KiB (1 KiB)
MAX_SIZE = 5 * 1024  # Maximum size in KiB (5 MiB)

def create_single_file(filename):
    filesize_kb = random.randint(MIN_SIZE, MAX_SIZE)
    with open(filename, 'wb') as f:
        f.write(os.urandom(filesize_kb * 1024))
    return filesize_kb

def create_random_files(directory):
    num_files = random.randint(MIN_FILES, MAX_FILES)
    print(f"Creating {num_files} files in directory: {directory}")
    total_size = 0
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:  # Reduced max workers for less strain
        futures = [executor.submit(create_single_file, directory / f"file_{i}.bin") for i in range(1, num_files + 1)]
        
        for future in concurrent.futures.as_completed(futures):
            total_size += future.result()

    print(f"Finished creating files in directory: {directory}, Total size: {total_size // 1024} MiB")

def create_directories_and_files(current_depth, current_dir):
    if current_depth < MAX_DEPTH:
        num_subdirs = random.randint(1, 3)  # Reduced subdirectories for performance
        subdirs = []
        for i in range(num_subdirs):
            subdir = current_dir / f"dir_{current_depth}_{i}"
            subdir.mkdir(parents=True, exist_ok=True)
            subdirs.append(subdir)
        
        for subdir in subdirs:
            create_directories_and_files(current_depth + 1, subdir)

    create_random_files(current_dir)

if __name__ == "__main__":
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Starting directory structure creation at base directory: {BASE_DIR}")
    create_directories_and_files(1, BASE_DIR)
    print("Directory structure with random files created successfully.")