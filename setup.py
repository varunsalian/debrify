from setuptools import setup, find_packages

# Read the contents of requirements.txt
with open('requirements.txt', 'r') as f:
    required_packages = f.readlines()

# Clean up the list (remove any unwanted whitespace)
required_packages = [pkg.strip() for pkg in required_packages]

setup(
    name="debrify",
    version="1.0.0",
    packages=find_packages(),
    include_package_data=True,  # Ensure package data is included
    install_requires=required_packages,  # Add the dependencies from requirements.txt
    entry_points={
        "console_scripts": [
            "debrify=debrify.main:main",
        ],
    },
)
