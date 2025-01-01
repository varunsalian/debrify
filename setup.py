from setuptools import setup, find_packages

# Read the contents of requirements.txt
with open('requirements.txt', 'r') as f:
    required_packages = f.readlines()

# Clean up the list (remove any unwanted whitespace)
required_packages = [pkg.strip() for pkg in required_packages]

setup(
    name="debrify",
    version="0.0.2",
    author="Varun Salian",
    author_email="varunbsalian@gmail.com",
    description="A CLI tool to search and add magnet into your real-debrid account",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    url="https://github.com/varunsalian/debrify",
    packages=find_packages(),
    include_package_data=True,
    install_requires=required_packages,
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "debrify=debrify.main:main",
        ],
    },
)
