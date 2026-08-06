import os
import socket
import datetime
from typing import List, Tuple
from flask import Flask, flash, render_template, request, redirect, url_for

# Initialize Flask application
app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

# Directory where the Azure file share is mounted in the container. The app talks to the share
# through the file system only: no Azure SDK, no connection string, no account key. Everything
# that makes the share reachable (SMB or NFS, pre-created or provisioned on demand) is handled by
# the Azure Files CSI driver when it mounts the volume into the pod.
activities_dir: str | None = None

# Suffix of the files holding the activities, one file per activity.
ACTIVITY_FILE_SUFFIX: str = "-activity.txt"

# Name of the pod serving the request, shown in the UI. All replicas mount the same file share, so
# an activity added through one pod is served by every other pod as well.
pod_name: str = os.environ.get("HOSTNAME", socket.gethostname())

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[str, str]] = []

def get_environment_variables():
    """Get the value of an environment variable or raise an error if not set."""
    global activities_dir
    try:
        # Get the mount point of the Azure file share from an environment variable
        activities_dir = os.environ.get("ACTIVITIES_DIR", "/data")

        if not activities_dir:
            raise ValueError("The ACTIVITIES_DIR environment variable is set to an empty value.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except Exception as ex:
        print(f"An error occurred: {ex}")

def get_activities_dir():
    """Return the mounted directory holding the activities, or None when it is not usable."""
    global activities_dir
    try:
        print(f"Resolving the activities directory...")

        if not activities_dir:
            raise ValueError("Activities directory is not set. Please set the ACTIVITIES_DIR environment variable.")

        # A missing directory means the Azure file share was not mounted into the container: the app
        # is not able to create the mount point itself, so this must fail loudly instead of writing
        # to the container file system, where the data would be invisible to the other replicas and
        # lost on restart.
        if not os.path.isdir(activities_dir):
            raise ValueError(f"Activities directory '{activities_dir}' does not exist. Is the Azure file share mounted?")

        if not os.access(activities_dir, os.W_OK | os.X_OK):
            raise ValueError(
                f"Activities directory '{activities_dir}' is not writable by uid {os.geteuid()}. "
                "Check the mount options of the volume (SMB) or the ownership of the share (NFS)."
            )

        print(f"Activities directory '{activities_dir}' resolved successfully.")
        return activities_dir
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
        return None
    except Exception as ex:
        print(f"An error occurred while resolving the activities directory: {ex}")
        return None

def create_activities_dir_if_not_exists():
    """Create the activities directory under the mount point if it does not already exist."""
    global activities_dir
    try:
        if not activities_dir:
            raise ValueError("Activities directory is not set. Please call get_activities_dir() first.")

        # The mount point itself always exists (the kubelet creates it when it mounts the volume),
        # so this only ever creates a subdirectory when ACTIVITIES_DIR points below the mount point.
        print(f"Creating activities directory '{activities_dir}' if it does not exist.")
        os.makedirs(activities_dir, exist_ok=True)
        print(f"Activities directory '{activities_dir}' is ready.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except OSError as ose:
        print(f"An error occurred while creating the activities directory: {ose}")
    except Exception as ex:
        print(f"An error occurred while creating the activities directory: {ex}")

def read_activities_from_dir():
    """Read all the activity files from the activities directory."""
    global activities_dir, activities
    try:
        if not activities_dir:
            raise ValueError("Activities directory is not set. Please call get_activities_dir() first.")

        # Sorted by name, which sorts by creation timestamp: the file name is the timestamp
        names = sorted(name for name in os.listdir(activities_dir) if name.endswith(ACTIVITY_FILE_SUFFIX))

        for name in names:
            path = os.path.join(activities_dir, name)

            if not os.path.isfile(path):
                continue

            # Read the file content
            with open(path, "r", encoding="utf-8") as file:
                content = file.read()

            print(f"Found activity file: {name} with size {os.path.getsize(path)} bytes")
            print(f"Content of activity file '{name}': {content}")
            activities.append((name, content))
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except OSError as ose:
        print(f"An error occurred while reading the activity files: {ose}")
    except Exception as ex:
        print(f"An error occurred while reading the activity files: {ex}")

def write_activity(name: str | None, content: str | None):
    """Create or overwrite an activity file in the activities directory."""
    global activities_dir

    # Check if name and content are provided
    if not name or not content:
        raise ValueError("Both 'name' and 'content' must be provided to write an activity.")

    try:
        if not activities_dir:
            raise ValueError("Activities directory is not set. Please call get_activities_dir() first.")

        # Reject a name that would escape the activities directory
        if os.path.basename(name) != name:
            raise ValueError(f"Invalid activity name '{name}': it must not contain a path separator.")

        path = os.path.join(activities_dir, name)

        print(f"Writing activity file '{name}' in directory '{activities_dir}'.")
        with open(path, "w", encoding="utf-8") as file:
            file.write(content)
        print(f"Activity file '{name}' written successfully.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except OSError as ose:
        print(f"An error occurred while writing the activity file: {ose}")
    except Exception as ex:
        print(f"An error occurred while writing the activity file: {ex}")

def delete_activity(name: str):
    """Delete an activity file from the activities directory."""
    global activities_dir
    try:
        if not activities_dir:
            raise ValueError("Activities directory is not set. Please call get_activities_dir() first.")

        if os.path.basename(name) != name:
            raise ValueError(f"Invalid activity name '{name}': it must not contain a path separator.")

        path = os.path.join(activities_dir, name)

        print(f"Deleting activity file '{name}' from directory '{activities_dir}'.")
        os.remove(path)
        print(f"Activity file '{name}' deleted successfully.")
    except ValueError as ve:
        print(f"Configuration Error: {ve}")
    except FileNotFoundError:
        print(f"Activity file '{name}' does not exist in directory '{activities_dir}'.")
    except OSError as ose:
        print(f"An error occurred while deleting the activity file: {ose}")
    except Exception as ex:
        print(f"An error occurred while deleting the activity file: {ex}")

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        row_id = request.form.get('row_id', '').strip()
        activity = request.form.get('activity', '').strip()
        if activity:
            if row_id:
                # Overwrite the content of the existing activity file in place
                write_activity(row_id, activity)
                for i, act in enumerate(activities):
                    if act[0] == row_id:
                        activities[i] = (row_id, activity)
                        break
                flash('Activity updated successfully.')
            else:
                # Generate a unique file name with a timestamp
                timestamp = datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
                name = f"{timestamp}{ACTIVITY_FILE_SUFFIX}"
                write_activity(name, activity)
                activities.append((name, activity))
                flash('Activity added successfully.')
        return redirect(url_for('index'))

    # Always reload the activities from the Azure file share on GET
    activities.clear()
    read_activities_from_dir()
    return render_template('index.html', activities=activities, pod_name=pod_name)

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id):
    if 0 <= activity_id < len(activities):
        delete_activity(activities[activity_id][0])
        activities.pop(activity_id)
        flash('Activity deleted successfully.')
    return redirect(url_for('index'))

# Initialize the application and the activities directory when the module is loaded.
# This ensures that the setup runs regardless of how the app is started (e.g., via 'flask run' or directly).
get_environment_variables()
if get_activities_dir():
    # Create the activities directory if it does not exist
    create_activities_dir_if_not_exists()

    # Read the existing activity files from the Azure file share, if any
    read_activities_from_dir()

if __name__ == '__main__':
    app.run(debug=True)
