import os
# pyrefly: ignore [missing-import]
from roboflow import Roboflow

def download_dataset():
    """
    Downloads the dataset from Roboflow using the Roboflow SDK.
    Requires the following environment variables:
    - ROBOFLOW_API_KEY
    - ROBOFLOW_WORKSPACE
    - ROBOFLOW_PROJECT
    - ROBOFLOW_VERSION (optional, defaults to 1)
    """
    api_key = os.environ.get("ROBOFLOW_API_KEY")
    if not api_key:
        print("Please set the ROBOFLOW_API_KEY environment variable.")
        return

    workspace_name = os.environ.get("ROBOFLOW_WORKSPACE")
    project_name = os.environ.get("ROBOFLOW_PROJECT")
    version = int(os.environ.get("ROBOFLOW_VERSION", 1))

    if not all([workspace_name, project_name]):
        print("Please set ROBOFLOW_WORKSPACE and ROBOFLOW_PROJECT environment variables.")
        return

    rf = Roboflow(api_key=api_key)
    project = rf.workspace(workspace_name).project(project_name)
    
    # Download dataset into data/raw/
    # 'folder' format structures it as class-separated folders
    print(f"Downloading {project_name} (v{version}) from {workspace_name}...")
    dataset = project.version(version).download("folder", location="data/raw/")
    
    print(f"Dataset downloaded successfully to {dataset.location}")

if __name__ == "__main__":
    download_dataset()
