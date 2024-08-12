# QFS File Lock Script

## Why File Locking? 

File locking in a Qumulo file system is beneficial for customers needing to comply with immutable data retention policies, whether required by company policies or mandated by regulations. It provides a mechanism to WORM protect (Write Once Read Many) files, ensuring that data, once written, cannot be modified or deleted until a specified retention period has been reached. This feature is especially useful in industries like finance, healthcare, and legal sectors, where data integrity and compliance are critical. Qumulo’s file locking capability protects against accidental or malicious data alterations, making it a valuable tool for long-term data preservation.

<p align="center">
  <img src="qfs_filelock_process_flow_diagram.png" alt="QFS File Lock Process Flow Diagram">
</p>

<p align="center">
QFS File Lock Process Flow Diagram
</p>

## Overview 

The `qfs_filelock.py` script monitors directories on a Qumulo cluster for changes such as new file creation. The script leverages the Qumulo SDK/API for interacting with the file system, making it a powerful tool for administrators looking to enforce strict data protection policies on their Qumulo storage clusters.

It listens for events via [SSE Payload Notification Types](#sse-payload-notification-types), streaming JSON-encoded notifications to the client. The file notifications can be specified based on the available types listed [here](#sse-payload-notification-types). 

When changes are detected, the script attempts to apply a Write Once Read Many (WORM) lock to the affected file, ensuring the integrity and immutability of critical data. Notifications are processed serially, but customers can modify the script to meet their requirements. It also allows for recursive monitoring of all subdirectories and includes a debug mode for detailed logging. 

> *Note: Performance may be impacted when there are many or deeply nested subdirectories to monitor, or when more than 100,000 files exist in a single directory.*

## Installation

To use the `qfs_filelock.py` script, you'll need to install the required Python packages. The following instructions assume you are running Ubuntu, however this script can also be run on Windows, assuming you have python3 and required packages installed.

### Prerequisites

1. Ensure python3 is installed:

    ```bash
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip
    ```

2. Install the necessary Python packages:

    ```bash
    pip3 install argparse configparser json logging os re requests sys time urllib3 warnings datetime qumulo-api
    ```

    For Windows, the same `pip3 install` command can be used from your Command Prompt or PowerShell.

3. Ensure you are using a version of the Qumulo Python SDK >= 7.2.1 
```
$ sudo pip show qumulo-api | grep Version
Version: 7.2.1
```

### Installing the Script

1. Clone the repository:

    ```bash
    git clone https://github.com/Qumulo/filelock.git
    cd filelock
    ```

2. Ensure the script is executable (on Unix-like systems):

    ```bash
    chmod +x qfs_filelock.py
    ```

3. Create the configuration file, example below.

`qfs_filelock_config.ini`:

```ini
[DEFAULT]
API_HOST = qumulo-cluster.example.com
API_PORT = 8000
USERNAME = admin
PASSWORD = your_password_here
```

## Getting Started

The script offers various options based on your monitoring and locking needs.

### Basic Usage

1. **Monitoring a Specific Directory by File ID.**

    *(A directory in a file system utilizes an inode similar to a file, which is why it’s referred to as a file id)*

    ```bash
    ./qfs_filelock.py --file-id <FILE_ID> --config-file <CONFIG_FILE_PATH>
    ```

2. **Monitoring a Directory by Path:**

    ```bash
    ./qfs_filelock.py --directory-path <DIRECTORY_PATH> --config-file <CONFIG_FILE_PATH>
    ```

3. **Enabling Debug Mode:**

    Debug mode provides detailed logging to help diagnose issues.

    ```bash
    ./qfs_filelock.py --directory-path <DIRECTORY_PATH> --config-file <CONFIG_FILE_PATH> --debug
    ```

4. **Recursive Monitoring:**

    To monitor all subdirectories within a specified directory:

    ```bash
    ./qfs_filelock.py --directory-path <DIRECTORY_PATH> --config-file <CONFIG_FILE_PATH> --recursive
    ```

5. **Setting Polling Interval:**

    By default, the script polls for notifications every 15 seconds. This can be adjusted using the `--interval` option, including "0" which locks the file immediately.

    ```bash
    ./qfs_filelock.py --directory-path <DIRECTORY_PATH> --config-file <CONFIG_FILE_PATH> --interval 30
    ```

    **Note on Timing:** You may need to adjust this interval based on the types of notifications being monitored and/or the size of the file being written. For example, if you include `child_file_added` and `child_data_written`, it is possible that the file is locked before the data is fully written.

6. **Saving Output to a File:**

    You can save the output to a file instead of printing it to STDOUT by specifying the `--output` option:

    ```bash
    ./qfs_filelock.py --directory-path <DIRECTORY_PATH> --config-file <CONFIG_FILE_PATH> --output /path/to/output.log
    ```

### Example Execution

```bash
./qfs_filelock.py --directory-path /data/important_files --config-file ~/qfs_filelock_config.ini --recursive --debug --interval 20
```

This command monitors the `/data/important_files` directory and all its subdirectories for changes, locks files upon changes, and logs detailed debug information.

## SSE Payload Notification Types

The following table describes the various SSE payload notification types. For more details, refer to the [Qumulo Documentation on Watching File Attribute and Directory Changes](https://docs.qumulo.com/administrator-guide/watching-file-attribute-directory-changes/rest.html).

| Notification Type            | Description                                                                 |
|------------------------------|-----------------------------------------------------------------------------|
| `child_acl_changed`           | ACL for the listed file or directory has been modified.                     |
| `child_atime_changed`         | `atime` (access time) of the listed file or directory has been modified.    |
| `child_btime_changed`         | `btime` (creation time) of the listed file or directory has been modified.  |
| `child_mtime_changed`         | `mtime` (modification time) of the listed file or directory has been modified. |
| `child_data_written`          | Data has been written to the listed file.                                   |
| `child_dir_added`             | The listed directory has been created.                                      |
| `child_dir_removed`           | The listed directory has been removed.                                      |
| `child_dir_moved_from`        | The listed directory has been moved from its location.                      |
| `child_dir_moved_to`          | The listed directory has been moved to a new location.                      |
| `child_file_added`            | The listed file has been added to the directory.                            |
| `child_file_removed`          | The listed file has been removed from the directory.                        |
| `child_file_moved_from`       | The listed file has been moved from its location.                           |
| `child_file_moved_to`         | The listed file has been moved to a new location.                           |
| `child_extra_attrs_changed`   | Extra attributes of the listed file or directory have been modified.        |

## Helpful Commands

Authenticate to the Qumulo `qq` CLI prior to running these commands. For example: `qq --host X.X.X.X login -u admin -p your_password_here`

1. **Determining a Directory's File Number:**

    You can determine a directory's file number using the Qumulo `qq` CLI command:

    ```bash
    qq --host X.X.X.X fs_file_get_attr --path /path/to/directory | jq .file_number
    ```

2. **Locking a File Using the CLI:**

    You can manually lock a file using the Qumulo `qq` CLI command by path or the directories file number (id):

    ```bash
    qq --host X.X.X.X fs_file_set_lock --path /path/to/directory/this_is_a_locked.file --days 1
    ```

    ```bash
    qq --host X.X.X.X fs_file_set_lock --file-id 133742 --days 1
    ```

3. **Verifying if a File is Locked**

    To verify if a file has been successfully locked, you can use the following Qumulo `qq` CLI command:

    ```bash
    qq --host X.X.X.X fs_file_get_attr --path /path/to/directory/this_is_a_locked.file --retrieve-file-lock | jq .lock
    ```

    This command retrieves the file's attributes, including the lock status, and displays it using `jq`.


### Troubleshooting

The script includes a debug mode, has verbose logging, and you can save the output to a file for further analysis.  

- The debug mode that can be enabled with the `--debug` flag. 
   - When debug mode is enabled, the script generates detailed log entries that can be useful for troubleshooting. 
   - The logging is controlled by Python's `logging` module, which allows for flexible log management.

- In addition to printing log messages to the console, you can also save the output to a file by using the `--output` option. 
   - This is particularly useful if you need to retain logs for audit purposes or further analysis.

## Relevant Links

- [Watching for File Attribute and Directory Changes Using REST](https://docs.qumulo.com/administrator-guide/watching-file-attribute-directory-changes/rest.html)
- [Qumulo REST API Guide](https://docs.qumulo.com/rest-api-guide/)
- [Qumulo Documentation Home](https://docs.qumulo.com/)
- [Qumulo Official Website](https://qumulo.com/)
- [Qumulo Search](https://qumulo.com/search.html)
- [Qumulo Resources](https://qumulo.com/resources/)

## FAQ

1. **Is this auditable?**

   Yes, the script uses the existing auditing system.

2. **Who can delete a file?**

   There is an RBAC "LOCK_ADMIN" privilege required to remove legal holds.

3. **Can I put an entire directory on legal hold?**

   File locking is performed on a per-file basis today; you cannot lock directories.

4. **How can I see all files that are locked on a cluster?**

   Currently, there is no built-in way to list all locked files; you would need to use a custom script.

## About the Author

This script was developed by Kevin McDonald (KMac) kmac@qumulo.com in August 2024. Qumulo, Inc. is a leader in scalable file storage solutions, and this script reflects our commitment to providing robust tools for data management and protection. If you have any questions or need further assistance, please contact us at support@qumulo.com.
