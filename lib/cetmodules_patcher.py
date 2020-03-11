
import os
import re

def cetmodules_dir_patcher(dir, proj, vers):
    for rt, drs, fnames in os.walk(dir):
        if "CMakeLists.txt" in fnames:
            cetmodules_file_patcher(rt + "/CMakeList.txt", rt == dir, proj, vers)

cmake_min_re =     re.compile("cmake_minimum_required\((\d*\.\d*)\)")
cmake_project_re = re.compile("project\(\s*(\S*)(.*)\)")
cmake_find_ups_re  = re.compile("find_ups_product\(\s*(\S*).*\)")
boost_re = re.compile("\$\{BOOST_(\w*)_LIBRARY\}")
root_re = re.compile("\$\{ROOT_(\w*)\}")
tbb_re = re.compile("\$\{TBB}")
dir_re = re.compile("\$\{\([A-Z_]\)_DIR\}")
drop_re = re.compile("(_cet_check\()|(include\(CPack\))|(add_subdirectory\(\s*ups\s*\))")

def cetmodules_file_patcher(fname, toplevel, proj, vers):
    fin = open(fname,"r")
    fout = open(fname+".new", "w")
    need_cmake_min = True
    need_project = True

    for line in fin:
        line = line.rstrip()
        line = dir_re.sub(lambda x:'${%s_DIR}' % x.group(1).lower(), line)
        line = boost_re.sub(lambda x:'Boost::%s' % x.group(1).lower(), line)
        line = root_re.sub(lambda x: 'ROOT::%s%s' % (x.group(1)[0],x.group(1)[1:].lower()), line)
        line = tbb_re.sub('TBB:tbb', line)
        mat = drop_re.match(line)
        if mat: 
            continue
        mat = cmake_min_re.search(line)
        if mat:
            fout.write( "cmake_minimum_required(%s)\n" % (mat.group(1), str(max(float(mat.group(1)), 3.11))))
            need_cmake_min = False
            continue
        mat = cmake_project_re.search(line)
        if mat:
            if mat.group(2).find("VERSION") >= 0:
                fout.write( line + "\n" )
            else:
                fout.write( "project(%s VERSION %s LANGUAGE CXX)\n" % (mat.group(1),vers))
            need_project = False
            continue
        mat = cmake_find_ups_re.search(line)
        if mat:
            if need_cmake_min:
               fout.write("cmake_minimum_required(3.11)\n")
               need_cmake_min = False
            if need_project:
               fout.write("project( %s VERSION %s LANGUAGE CXX )" % (proj,vers))
               need_project = False

            newname = mat.group(1)

            if newname.find("lib") == 0:
               newname = newname[3:]

            if newname == "ifdhc":
               fout.write("cet_find_simple_package( ifdhc INCPATH_SUFFIXES inc INCPATH_VAR IFDHC_INC )\n")
            elif newname in ("wda", "ifbeam", "nucondb"):
               fout.write("cet_find_simple_package( %s )\n" % newname)
            else:
                fout.write("find_package( %s )\n" % newname )
            continue

        fout.write(line+"\n")
    fin.close()
    fout.close()

if __name__ == '__main__':
    import sys
    cetmodules_file_patcher(sys.argv[1], True, "foo","1.0")
