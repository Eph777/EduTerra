#!/usr/bin/env python3
import os
import sys
import json
import re
import urllib.request
import urllib.error
import urllib.parse
import tempfile
import zipfile
import shutil
import argparse

HEADERS = {'User-Agent': 'Luanti-Mod-Installer/1.0'}

# Built-in or standard game mods we should not download/install
IGNORED_MODS = {
    "default", "bucket", "doors", "fire", "stairs", "vessels", "wool", 
    "dye", "beds", "boats", "bones", "creative", "give_initial_stuff", 
    "key", "map", "screwdriver", "sfinv", "spawn", "tnt", "walls", "player_api"
}

def make_request(url):
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as response:
            return response.read()
    except urllib.error.URLError as e:
        print(f"Error requesting {url}: {e}", file=sys.stderr)
        return None

def fetch_json(url):
    data = make_request(url)
    if data:
        try:
            return json.loads(data.decode('utf-8'))
        except json.JSONDecodeError:
            pass
    return None

def parse_package_id(input_str):
    # Parse URL format (e.g. https://content.minetest.net/packages/Wuzzy/xdecor/)
    match = re.search(r'content\.(?:minetest\.net|luanti\.org)/packages/([^/]+)/([^/]+)', input_str)
    if match:
        return f"{match.group(1)}/{match.group(2)}"
    
    # Parse author/name format (e.g. Wuzzy/xdecor)
    if '/' in input_str:
        return input_str
        
    return None

def get_package_info(package_id):
    url = f"https://content.minetest.net/api/packages/{package_id}/"
    return fetch_json(url)

def get_dependencies(package_id):
    url = f"https://content.minetest.net/api/packages/{package_id}/dependencies/"
    return fetch_json(url)

def enable_mod_in_world(world_mt_path, mod_name):
    if not os.path.exists(world_mt_path):
        print(f"Warning: world.mt not found at {world_mt_path}. Cannot auto-enable.")
        return
    
    # Read existing world.mt lines
    with open(world_mt_path, 'r') as f:
        lines = f.readlines()
        
    # Remove any existing config line for this mod
    pattern = re.compile(rf"^load_mod_{mod_name}\s*=")
    lines = [line for line in lines if not pattern.match(line)]
    
    # Write back and append enabled flag
    lines.append(f"load_mod_{mod_name} = true\n")
    with open(world_mt_path, 'w') as f:
        f.writelines(lines)
    print(f"  -> Activated mod '{mod_name}' in world.mt")

def is_mod_enabled(world_mt_path, mod_name):
    if not os.path.exists(world_mt_path):
        return False
    try:
        with open(world_mt_path, 'r') as f:
            for line in f:
                if re.match(rf"^load_mod_{mod_name}\s*=\s*true", line):
                    return True
    except Exception:
        pass
    return False

def disable_mod_in_world(world_mt_path, mod_name):
    if not os.path.exists(world_mt_path):
        print(f"Warning: world.mt not found at {world_mt_path}. Cannot auto-disable.")
        return
    
    # Read existing world.mt lines
    with open(world_mt_path, 'r') as f:
        lines = f.readlines()
        
    # Remove any existing config line for this mod
    pattern = re.compile(rf"^load_mod_{mod_name}\s*=")
    lines = [line for line in lines if not pattern.match(line)]
    
    # Write back and append disabled flag
    lines.append(f"load_mod_{mod_name} = false\n")
    with open(world_mt_path, 'w') as f:
        f.writelines(lines)
    print(f"  -> Deactivated mod '{mod_name}' in world.mt")

def check_status(mod_name, mods_dir, world_mt_path):
    target_dir = os.path.join(mods_dir, mod_name)
    if not os.path.exists(target_dir):
        print(f"error:{mod_name}:not_found")
        return
        
    mods_in_package, is_modpack = get_installed_mods(target_dir)
    
    if is_modpack:
        # Check if any submod is enabled
        any_enabled = False
        submod_infos = []
        for m in mods_in_package:
            enabled = is_mod_enabled(world_mt_path, m)
            if enabled:
                any_enabled = True
            submod_infos.append((m, "enabled" if enabled else "disabled"))
            
        print(f"modpack:{mod_name}:{'enabled' if any_enabled else 'disabled'}")
        for sm_name, sm_status in submod_infos:
            print(f"submod:{sm_name}:{sm_status}")
    else:
        enabled = is_mod_enabled(world_mt_path, mod_name)
        print(f"mod:{mod_name}:{'enabled' if enabled else 'disabled'}")

def toggle_mod(mod_name, mods_dir, world_mt_path):
    target_dir = os.path.join(mods_dir, mod_name)
    if not os.path.exists(target_dir):
        print(f"Error: Mod directory '{mod_name}' not found in {mods_dir}")
        sys.exit(1)
        
    mods_in_package, is_modpack = get_installed_mods(target_dir)
    
    # Determine if the mod/modpack is currently enabled
    # For a modpack, it is enabled if at least one submod is enabled
    any_enabled = False
    for m in mods_in_package:
        if is_mod_enabled(world_mt_path, m):
            any_enabled = True
            break
            
    if any_enabled:
        # Disable all
        print(f"Deactivating mod/modpack '{mod_name}'...")
        if is_modpack:
            remove_mod_from_world(world_mt_path, mod_name)
        for m in mods_in_package:
            disable_mod_in_world(world_mt_path, m)
    else:
        # Enable all
        print(f"Activating mod/modpack '{mod_name}'...")
        if is_modpack:
            remove_mod_from_world(world_mt_path, mod_name)
        for m in mods_in_package:
            enable_mod_in_world(world_mt_path, m)
            
        resolve_dependencies_for_local_mods(mods_in_package, target_dir, mods_dir, world_mt_path)

def get_mod_name_from_conf(conf_path):
    if not os.path.exists(conf_path):
        return None
    try:
        with open(conf_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                # Remove comments and whitespace
                line = line.split('#')[0].strip()
                if '=' in line:
                    key, val = line.split('=', 1)
                    if key.strip().lower() == 'name':
                        return val.strip()
    except Exception as e:
        print(f"Warning: failed to read config file {conf_path}: {e}")
    return None

def remove_mod_from_world(world_mt_path, mod_name):
    if not os.path.exists(world_mt_path):
        return
    with open(world_mt_path, 'r') as f:
        lines = f.readlines()
    pattern = re.compile(rf"^load_mod_{mod_name}\s*=")
    new_lines = [line for line in lines if not pattern.match(line)]
    if len(new_lines) != len(lines):
        with open(world_mt_path, 'w') as f:
            f.writelines(new_lines)
        print(f"  -> Cleaned up legacy/invalid mod entry '{mod_name}' from world.mt")

def get_installed_mods(installed_dir_path):
    # Returns a list of technical mod names inside the installed directory.
    is_modpack = False
    for filename in ["modpack.conf", "modpack.txt"]:
        if os.path.exists(os.path.join(installed_dir_path, filename)):
            is_modpack = True
            break
            
    if is_modpack:
        mods = []
        for entry in sorted(os.listdir(installed_dir_path)):
            subdir = os.path.join(installed_dir_path, entry)
            if os.path.isdir(subdir):
                # Check if it is a mod directory
                has_mod_conf = os.path.exists(os.path.join(subdir, "mod.conf"))
                has_init_lua = os.path.exists(os.path.join(subdir, "init.lua"))
                if has_mod_conf or has_init_lua:
                    mod_name = None
                    if has_mod_conf:
                        mod_name = get_mod_name_from_conf(os.path.join(subdir, "mod.conf"))
                    if not mod_name:
                        mod_name = entry
                    mods.append(mod_name)
        return mods, True
    else:
        mod_conf_path = os.path.join(installed_dir_path, "mod.conf")
        mod_name = get_mod_name_from_conf(mod_conf_path)
        if not mod_name:
            mod_name = os.path.basename(installed_dir_path)
        return [mod_name], False

def install_package(package_id, mods_dir, world_mt_path):
    info = get_package_info(package_id)
    if not info:
        print(f"Error: Could not retrieve package details for {package_id}")
        return None
        
    if info.get("type") != "mod":
        print(f"Skipping package {package_id} because its type is '{info.get('type')}' (only 'mod' packages are supported)")
        return None

    download_url = f"https://content.minetest.net/packages/{package_id}/download/"
    
    # Download zip file
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as temp_zip:
        temp_zip_path = temp_zip.name
        
    try:
        print(f"Downloading {package_id} from {download_url}...")
        req = urllib.request.Request(download_url, headers=HEADERS)
        with urllib.request.urlopen(req) as response, open(temp_zip_path, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
            
        # Extract zip file
        extract_dir = tempfile.mkdtemp()
        with zipfile.ZipFile(temp_zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        # Locate mod directory (sometimes nested inside zip)
        subdirs = [os.path.join(extract_dir, d) for d in os.listdir(extract_dir) if os.path.isdir(os.path.join(extract_dir, d))]
        if not subdirs:
            print(f"Error: No mod directory found in ZIP for {package_id}")
            return None
            
        mod_root = subdirs[0]
        mod_name = os.path.basename(mod_root)
        
        # Clean mod name (remove -master / version suffixes)
        clean_mod_name = re.sub(r'-[0-9a-fA-F]+$|-master$', '', mod_name)
        target_dir = os.path.join(mods_dir, clean_mod_name)
        
        # Install files
        if os.path.exists(target_dir):
            print(f"  -> Overwriting existing mod '{clean_mod_name}' files...")
            shutil.rmtree(target_dir)
            
        shutil.move(mod_root, target_dir)
        print(f"  -> Installed mod '{clean_mod_name}' to {target_dir}")
        
        # Enable in world.mt
        if world_mt_path:
            mods_to_enable, is_modpack = get_installed_mods(target_dir)
            if is_modpack:
                remove_mod_from_world(world_mt_path, clean_mod_name)
            for m in mods_to_enable:
                enable_mod_in_world(world_mt_path, m)
            
        return clean_mod_name
    finally:
        if os.path.exists(temp_zip_path):
            os.remove(temp_zip_path)
        if 'extract_dir' in locals() and os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

def find_best_candidate(dep_name, candidate_packages):
    # First pass: try candidates where the package name matches the dependency name exactly
    for pkg in candidate_packages:
        if '/' in pkg:
            _, pkg_name = pkg.split('/', 1)
            if pkg_name == dep_name:
                info = get_package_info(pkg)
                if info and info.get("type") == "mod":
                    return pkg
                    
    # Second pass: check other candidates in order
    for pkg in candidate_packages:
        info = get_package_info(pkg)
        if info and info.get("type") == "mod":
            return pkg
            
    return None

def resolve_and_install(initial_package_id, mods_dir, world_mt_path):
    installed_packages = set()
    queue = [initial_package_id]
    
    while queue:
        current_pkg = queue.pop(0)
        if current_pkg in installed_packages:
            continue
            
        print(f"\nResolving: {current_pkg}")
        
        # Find dependencies of the current package
        deps_data = get_dependencies(current_pkg)
        if deps_data and current_pkg in deps_data:
            dependencies = deps_data[current_pkg]
            for dep in dependencies:
                # We only follow hard (non-optional) dependencies
                if not dep.get("is_optional", False):
                    dep_name = dep.get("name")
                    if dep_name in IGNORED_MODS:
                        continue
                        
                    candidate_packages = dep.get("packages", [])
                    if candidate_packages:
                        # Choose the best mod package provider
                        candidate = find_best_candidate(dep_name, candidate_packages)
                        if candidate:
                            if candidate not in installed_packages and candidate not in queue:
                                print(f"  -> Found hard dependency '{dep_name}': queueing package '{candidate}'")
                                queue.append(candidate)
                        else:
                            print(f"  -> Warning: Hard dependency '{dep_name}' exists, but no valid 'mod' package provides it on ContentDB.")
                    else:
                        print(f"  -> Warning: Dependency '{dep_name}' has no registered package providers on ContentDB.")
        
        # Install the actual package
        installed_name = install_package(current_pkg, mods_dir, world_mt_path)
        if installed_name:
            installed_packages.add(current_pkg)

def get_local_dependencies(mod_dir):
    deps = set()
    
    # 1. Check mod.conf
    mod_conf_path = os.path.join(mod_dir, "mod.conf")
    if os.path.exists(mod_conf_path):
        try:
            with open(mod_conf_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.split('#')[0].strip()
                    if '=' in line:
                        key, val = line.split('=', 1)
                        if key.strip().lower() == 'depends':
                            for dep in val.split(','):
                                dep = dep.strip()
                                if dep:
                                    deps.add(dep)
        except Exception as e:
            print(f"Warning: failed to read config file {mod_conf_path}: {e}")
            
    # 2. Check depends.txt (legacy)
    depends_txt_path = os.path.join(mod_dir, "depends.txt")
    if os.path.exists(depends_txt_path):
        try:
            with open(depends_txt_path, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    line = line.split('#')[0].strip()
                    if line:
                        if line.endswith('?'):
                            continue
                        deps.add(line)
        except Exception as e:
            print(f"Warning: failed to read depends.txt {depends_txt_path}: {e}")
            
    return sorted(list(deps))

def search_contentdb_for_mod(dep_name):
    url = f"https://content.minetest.net/api/packages/?q={urllib.parse.quote(dep_name)}&type=mod"
    packages = fetch_json(url)
    if not packages:
        return None
    for pkg in packages:
        if pkg.get("name") == dep_name:
            return f"{pkg.get('author')}/{pkg.get('name')}"
    return None

def resolve_dependencies_for_local_mods(mods_list, target_dir, mods_dir, world_mt_path):
    all_deps = set()
    local_mod_names = set(mods_list)
    
    # If it is a modpack, we check its sub-directories
    is_modpack = os.path.exists(os.path.join(target_dir, "modpack.conf")) or os.path.exists(os.path.join(target_dir, "modpack.txt"))
    if is_modpack:
        for entry in os.listdir(target_dir):
            subdir = os.path.join(target_dir, entry)
            if os.path.isdir(subdir):
                if os.path.exists(os.path.join(subdir, "mod.conf")) or os.path.exists(os.path.join(subdir, "init.lua")):
                    all_deps.update(get_local_dependencies(subdir))
    else:
        all_deps.update(get_local_dependencies(target_dir))
        
    unresolved_deps = []
    for dep in all_deps:
        if dep in IGNORED_MODS or dep in local_mod_names:
            continue
            
        # Check if already installed
        installed = False
        if os.path.exists(os.path.join(mods_dir, dep)):
            installed = True
        else:
            # Check all installed folders to see if any sub-mod has this name
            for d in os.listdir(mods_dir):
                parent_dir = os.path.join(mods_dir, d)
                if os.path.isdir(parent_dir):
                    submods, _ = get_installed_mods(parent_dir)
                    if dep in submods:
                        installed = True
                        break
        if not installed:
            unresolved_deps.append(dep)
            
    for dep in unresolved_deps:
        print(f"Resolving missing dependency: {dep}")
        package_id = search_contentdb_for_mod(dep)
        if package_id:
            print(f"  -> Found package '{package_id}' on ContentDB. Installing...")
            resolve_and_install(package_id, mods_dir, world_mt_path)
        else:
            print(f"  -> Warning: Could not find package on ContentDB for dependency '{dep}'")

def install_local_zip(zip_path, mods_dir, world_mt_path):
    if not os.path.exists(zip_path):
        print(f"Error: Local zip file '{zip_path}' not found.")
        sys.exit(1)
        
    print(f"Installing local mod archive: {os.path.basename(zip_path)}...")
    
    extract_dir = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        mod_root = None
        for root, dirs, files in os.walk(extract_dir):
            if any(f in ["modpack.conf", "modpack.txt", "mod.conf", "init.lua"] for f in files):
                mod_root = root
                break
                
        if not mod_root:
            subdirs = [os.path.join(extract_dir, d) for d in os.listdir(extract_dir) if os.path.isdir(os.path.join(extract_dir, d))]
            if subdirs:
                mod_root = subdirs[0]
                
        if not mod_root:
            print(f"Error: No mod directory found in ZIP.")
            return None
            
        mod_name = os.path.basename(mod_root)
        if mod_root == extract_dir:
            mod_name = os.path.splitext(os.path.basename(zip_path))[0]
            
        clean_mod_name = re.sub(r'-[0-9a-fA-F]+$|-master$', '', mod_name)
        target_dir = os.path.join(mods_dir, clean_mod_name)
        
        if mod_root == extract_dir:
            if os.path.exists(target_dir):
                print(f"  -> Overwriting existing mod '{clean_mod_name}' files...")
                shutil.rmtree(target_dir)
            os.makedirs(target_dir, exist_ok=True)
            for entry in os.listdir(extract_dir):
                shutil.move(os.path.join(extract_dir, entry), os.path.join(target_dir, entry))
        else:
            if os.path.exists(target_dir):
                print(f"  -> Overwriting existing mod '{clean_mod_name}' files...")
                shutil.rmtree(target_dir)
            shutil.move(mod_root, target_dir)
            
        print(f"  -> Installed mod '{clean_mod_name}' to {target_dir}")
        
        mods_to_enable, is_modpack = get_installed_mods(target_dir)
        if is_modpack:
            remove_mod_from_world(world_mt_path, clean_mod_name)
        for m in mods_to_enable:
            enable_mod_in_world(world_mt_path, m)
            
        resolve_dependencies_for_local_mods(mods_to_enable, target_dir, mods_dir, world_mt_path)
        
        return clean_mod_name
    finally:
        if os.path.exists(extract_dir):
            shutil.rmtree(extract_dir)

def enable_only(mod_name, mods_dir, world_mt_path):
    target_dir = os.path.join(mods_dir, mod_name)
    if not os.path.exists(target_dir):
        print(f"Error: Mod directory '{mod_name}' not found in {mods_dir}")
        sys.exit(1)
        
    mods_to_enable, is_modpack = get_installed_mods(target_dir)
    
    if is_modpack:
        remove_mod_from_world(world_mt_path, mod_name)
        
    for m in mods_to_enable:
        enable_mod_in_world(world_mt_path, m)
        
    resolve_dependencies_for_local_mods(mods_to_enable, target_dir, mods_dir, world_mt_path)

def main():
    parser = argparse.ArgumentParser(description="Recursively install Luanti mods and dependencies from ContentDB or local zip.")
    parser.add_argument("input", nargs="?", help="ContentDB Package page URL, 'author/name', or local ZIP file path")
    parser.add_argument("--mods-dir", required=True, help="Path to the Luanti mods/ directory")
    parser.add_argument("--world-mt", help="Path to world.mt file to auto-enable mods")
    parser.add_argument("--enable-only", help="Only enable/activate the specified already-installed mod name in world.mt (including sub-mods if it is a modpack)")
    parser.add_argument("--toggle", help="Toggle the activation status of the specified mod/modpack in world.mt")
    parser.add_argument("--check-status", help="Print the details and activation status of the specified mod/modpack and its submods")
    
    args = parser.parse_args()
    
    # Ensure mods directory exists
    if not os.path.exists(args.mods_dir):
        os.makedirs(args.mods_dir, exist_ok=True)
        
    if args.enable_only:
        enable_only(args.enable_only, args.mods_dir, args.world_mt)
        print(f"\nMod '{args.enable_only}' activation complete!")
        sys.exit(0)
        
    if args.toggle:
        toggle_mod(args.toggle, args.mods_dir, args.world_mt)
        print(f"\nMod '{args.toggle}' status update complete!")
        sys.exit(0)

    if args.check_status:
        check_status(args.check_status, args.mods_dir, args.world_mt)
        sys.exit(0)

    if not args.input:
        parser.error("the following arguments are required: input (unless --enable-only, --toggle, or --check-status is specified)")
        
    # Check if input is a local ZIP file
    if os.path.isfile(args.input) and (args.input.endswith(".zip") or zipfile.is_zipfile(args.input)):
        install_local_zip(args.input, args.mods_dir, args.world_mt)
        print("\nLocal mod installation and dependency resolution complete!")
        sys.exit(0)
        
    package_id = parse_package_id(args.input)
    if not package_id:
        print("Error: Input must be a valid ContentDB URL, 'author/name', or a path to a local zip file.", file=sys.stderr)
        sys.exit(1)
        
    print(f"Target Mod ID detected: {package_id}")
    resolve_and_install(package_id, args.mods_dir, args.world_mt)
    print("\nMod installation and dependency resolution complete!")

if __name__ == "__main__":
    main()
