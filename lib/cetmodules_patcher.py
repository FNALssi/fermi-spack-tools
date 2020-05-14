
import sys
import os
import re

def fixrootlib(x):
    part = x.group(1)
    for lib in ("GenVector", "Core", "Imt", "RIO", "Net", "Hist", "Graf", "Graf3d", "Gpad", "ROOTVecOps", "Tree", "TreePlayer", "Rint", "Postscript", "Matrix", "Physics", "MathCore", "Thread", "MultiProc", "ROOTDataFrame"):
         if lib.lower() == part.lower():
              return 'ROOT::%s' % lib
    return 'ROOT::%s' % part.lower().capitalize()
        
def cetmodules_dir_patcher(dir, proj, vers):
    for rt, drs, fnames in os.walk(dir):
        if "CMakeLists.txt" in fnames:
            cetmodules_file_patcher(rt + "/CMakeLists.txt", rt == dir, proj, vers)
        for fname in fnames:
            if fname.endswith(".cmake"):
                cetmodules_file_patcher("%s/%s" % (rt, fname), rt == dir, proj, vers)

cmake_min_re =     re.compile("cmake_minimum_required\([VERSION ]*(\d*\.\d*).*\)")
cmake_project_re = re.compile("project\(\s*(\S*)(.*)\)")
cmake_ups_boost_re  = re.compile("find_ups_boost\(.*\)")
cmake_ups_root_re  = re.compile("find_ups_root\(.*\)")
cmake_find_ups_re  = re.compile("find_ups_product\(\s*(\S*).*\)")
cmake_find_cetbuild_re = re.compile("find_package\((cetbuildtools.*)\)")
cmake_find_lib_paths_re = re.compile("cet_find_library\((.*) PATHS ENV.*NO_DEFAULT_PATH")
boost_re = re.compile("\$\{BOOST_(\w*)_LIBRARY\}")
root_re = re.compile("\$\{ROOT_(\w*)_LIBRARY\}")
tbb_re = re.compile("\$\{TBB}")
dir_re = re.compile("\$\{\([A-Z_]\)_DIR\}")
drop_re = re.compile("(_cet_check\()|(include\(UseCPack\))|(add_subdirectory\(\s*ups\s*\))|(cet_have_qual\()|(check_ups_version\()")

def fake_check_ups_version(line, fout):
    p0 = line.find("PRODUCT_MATCHES_VAR ") + 20
    p1 = line.find(")")
    fout.write("set( %s True )\n" % line[p0:p1] )

def cetmodules_file_patcher(fname, toplevel=True, proj='foo', vers='1.0'):
    sys.stderr.write("Patching file '%s'\n" % fname)
    fin = open(fname,"r")
    fout = open(fname+".new", "w")
    need_cmake_min = toplevel
    need_project = toplevel
    drop_til_close = False

    for line in fin:
        line = line.rstrip()
        if drop_til_close:
            if line.find(")") > 0:
                drop_til_close = False
            if line.find("PRODUCT_MATCHES_VAR") > 0:
                fake_check_ups_version(line, fout)
            continue
        line = dir_re.sub(lambda x:'${%s_DIR}' % x.group(1).lower(), line)
        line = boost_re.sub(lambda x:'Boost::%s' % x.group(1).lower(), line)
        line = root_re.sub(fixrootlib, line)
        line = cmake_find_cetbuild_re.sub("find_package(cetmodules)", line)
        line = tbb_re.sub('TBB:tbb', line)

        mat = drop_re.search(line)
        if mat: 
            if line.find(")") < 0:
                drop_til_close = True
            if line.find("PRODUCT_MATCHES_VAR") > 0:
                fake_check_ups_version(line, fout)
            continue

        mat = cmake_min_re.search(line)
        if mat:
            fout.write( "cmake_minimum_required(VERSION %s)\n" % str(max(float(mat.group(1)), 3.11)))
            need_cmake_min = False
            continue
        
        mat = cmake_find_lib_paths_re.search(line)
        if mat:
            fout.write("cet_find_library(%s)\n" % mat.group(1))
            continue

        mat = cmake_project_re.search(line)
        if mat:
            if mat.group(2).find("VERSION") >= 0:
                fout.write( line + "\n" )
            else:
                fout.write( "project(%s VERSION %s LANGUAGES CXX)\n" % (mat.group(1),vers))
            need_project = False
            continue

        mat = cmake_ups_root_re.search(line)
        if mat:
            if need_cmake_min:
               fout.write("cmake_minimum_required(VERSION 3.11)\n")
               need_cmake_min = False
            if need_project:
               fout.write("project( %s VERSION %s LANGUAGES CXX )" % (proj,vers))
               need_project = False
              
            fout.write("find_package(ROOT COMPONENTS GenVector Core Imt RIO Net Hist Graf Graf3d Gpad ROOTVecOps Tree TreePlayer Rint Postscript Matrix Physics MathCore Thread MultiProc ROOTDataFrame)\n")
            continue

        mat = cmake_ups_boost_re.search(line)
        if mat:
            if need_cmake_min:
               fout.write("cmake_minimum_required(VERSION 3.11)\n")
               need_cmake_min = False
            if need_project:
               fout.write("project( %s VERSION %s LANGUAGES CXX )" % (proj,vers))
               need_project = False
            fout.write("find_package(Boost COMPONENTS system filesystem program_options date_time graph thread regex random)")
            continue

        mat = cmake_find_ups_re.search(line)
        if mat:
            if need_cmake_min:
               fout.write("cmake_minimum_required(VERSION 3.11)\n")
               need_cmake_min = False
            if need_project:
               fout.write("project( %s VERSION %s LANGUAGES CXX )" % (proj,vers))
               need_project = False

            newname = mat.group(1)

            if newname.find("lib") == 0:
               newname = newname[3:]

            if newname in ("clhep",):
               newname = newname.upper()

            if newname == "ifdhc":
               fout.write("cet_find_simple_package( ifdhc INCPATH_SUFFIXES inc INCPATH_VAR IFDHC_INC )\n")
            elif newname in ("wda", "ifbeam", "nucondb"):
               fout.write("cet_find_simple_package( %s INCPATH_VAR %s_inc )\n" % (newname, newname.upper()))
            else:
                fout.write("find_package( %s )\n" % newname )
            continue

        fout.write(line+"\n")

    fin.close()
    fout.close()
    if os.path.exists(fname+'.bak'):
        os.unlink(fname+'.bak')
    os.link(fname, fname+'.bak')
    os.rename(fname+'.new', fname)

if __name__ == '__main__':
    if len(sys.argv) != 4 or not os.path.isdir(sys.argv[1]):
        sys.stderr.write("usage: %s directory package-name package-version\n" % sys.argv[0])
        sys.exit(1)
    cetmodules_dir_patcher(sys.argv[1], sys.argv[2],sys.argv[3])
