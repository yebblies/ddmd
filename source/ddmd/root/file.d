
// Compiler implementation of the D programming language
// Copyright (c) 1999-2015 by Digital Mars
// All Rights Reserved
// written by Walter Bright
// http://www.digitalmars.com
// Distributed under the Boost Software License, Version 1.0.
// http://www.boost.org/LICENSE_1_0.txt

module ddmd.root.file;

import core.stdc.errno, core.stdc.stdio, core.stdc.stdlib, core.stdc.string, core.sys.posix.fcntl, core.sys.posix.sys.types, core.sys.posix.unistd, core.sys.posix.utime, core.sys.windows.windows;
import ddmd.root.array, ddmd.root.filename, ddmd.root.rmem;

version(Windows) alias WIN32_FIND_DATAA = WIN32_FIND_DATA;

struct File
{
    int _ref; // != 0 if this is a reference to someone else's buffer
    ubyte* buffer; // data for our file
    size_t len; // amount of data in buffer[]
    void* touchtime; // system time to use for file
    FileName* name; // name of our file
    extern(D) this(const(char)* n)
    {
        _ref = 0;
        buffer = null;
        len = 0;
        touchtime = null;
        name = new FileName(n);
    }

    extern(C++) static File* create(const(char)* n)
    {
        return new File(n);
    }

    /****************************** File ********************************/
    extern(D) this(const(FileName)* n)
    {
        _ref = 0;
        buffer = null;
        len = 0;
        touchtime = null;
        name = cast(FileName*)n;
    }

    extern(C++) ~this()
    {
        if (buffer)
        {
            if (_ref == 0)
                mem.free(buffer);
            version(Windows)
            {
                if (_ref == 2)
                    UnmapViewOfFile(buffer);
            }
        }
        if (touchtime)
            mem.free(touchtime);
    }

    extern(C++) char* toChars()
    {
        return name.toChars();
    }

    /*************************************
     */
    extern(C++) int read()
    {
        if (len)
            return 0; // already read the file
        version(Posix)
        {
            size_t size;
            ssize_t numread;
            int fd;
            stat_t buf;
            int result = 0;
            char* name;
            name = this.name.toChars();
            //printf("File::read('%s')\n",name);
            fd = open(name, O_RDONLY);
            if (fd == -1)
            {
                //printf("\topen error, errno = %d\n",errno);
                goto err1;
            }
            if (!_ref)
                .free(buffer);
            _ref = 0; // we own the buffer now
            //printf("\tfile opened\n");
            if (fstat(fd, &buf))
            {
                printf("\tfstat error, errno = %d\n", errno);
                goto err2;
            }
            size = cast(size_t)buf.st_size;
            buffer = cast(ubyte*).malloc(size + 2);
            if (!buffer)
            {
                printf("\tmalloc error, errno = %d\n", errno);
                goto err2;
            }
            numread = .read(fd, buffer, size);
            if (numread != size)
            {
                printf("\tread error, errno = %d\n", errno);
                goto err2;
            }
            if (touchtime)
                memcpy(touchtime, &buf, (buf).sizeof);
            if (close(fd) == -1)
            {
                printf("\tclose error, errno = %d\n", errno);
                goto err;
            }
            len = size;
            // Always store a wchar ^Z past end of buffer so scanner has a sentinel
            buffer[size] = 0; // ^Z is obsolete, use 0
            buffer[size + 1] = 0;
            return 0;
        err2:
            close(fd);
        err:
            .free(buffer);
            buffer = null;
            len = 0;
        err1:
            result = 1;
            return result;
        }
        else version(Windows)
        {
            DWORD size;
            DWORD numread;
            HANDLE h;
            int result = 0;
            char* name;
            name = this.name.toChars();
            h = CreateFileA(name, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, null);
            if (h == INVALID_HANDLE_VALUE)
                goto err1;
            if (!_ref)
                .free(buffer);
            _ref = 0;
            size = GetFileSize(h, null);
            buffer = cast(ubyte*).malloc(size + 2);
            if (!buffer)
                goto err2;
            if (ReadFile(h, buffer, size, &numread, null) != TRUE)
                goto err2;
            if (numread != size)
                goto err2;
            if (touchtime)
            {
                if (!GetFileTime(h, null, null, &(cast(WIN32_FIND_DATAA*)touchtime).ftLastWriteTime))
                    goto err2;
            }
            if (!CloseHandle(h))
                goto err;
            len = size;
            // Always store a wchar ^Z past end of buffer so scanner has a sentinel
            buffer[size] = 0; // ^Z is obsolete, use 0
            buffer[size + 1] = 0;
            return 0;
        err2:
            CloseHandle(h);
        err:
            .free(buffer);
            buffer = null;
            len = 0;
        err1:
            result = 1;
            return result;
        }
        else
        {
            assert(0);
        }
    }

    /*****************************
     * Read a file with memory mapped file I/O.
     */
    extern(C++) int mmread()
    {
        version(Posix)
        {
            return read();
        }
        else version(Windows)
        {
            HANDLE hFile;
            HANDLE hFileMap;
            DWORD size;
            char* name;
            name = this.name.toChars();
            hFile = CreateFileA(name, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
            if (hFile == INVALID_HANDLE_VALUE)
                goto Lerr;
            size = GetFileSize(hFile, null);
            //printf(" file created, size %d\n", size);
            hFileMap = CreateFileMappingA(hFile, null, PAGE_READONLY, 0, size, null);
            if (CloseHandle(hFile) != TRUE)
                goto Lerr;
            if (hFileMap is null)
                goto Lerr;
            //printf(" mapping created\n");
            if (!_ref)
                mem.free(buffer);
            _ref = 2;
            buffer = cast(ubyte*)MapViewOfFileEx(hFileMap, FILE_MAP_READ, 0, 0, size, null);
            if (CloseHandle(hFileMap) != TRUE)
                goto Lerr;
            if (buffer is null) // mapping view failed
                goto Lerr;
            len = size;
            //printf(" buffer = %p\n", buffer);
            return 0;
        Lerr:
            return GetLastError(); // failure
        }
        else
        {
            assert(0);
        }
    }

    /*********************************************
     * Write a file.
     * Returns:
     *      0       success
     */
    extern(C++) int write()
    {
        version(Posix)
        {
            int fd;
            ssize_t numwritten;
            char* name;
            name = this.name.toChars();
            fd = open(name, O_CREAT | O_WRONLY | O_TRUNC, (6 << 6) | (4 << 3) | 4);
            if (fd == -1)
                goto err;
            numwritten = .write(fd, buffer, len);
            if (len != numwritten)
                goto err2;
            if (close(fd) == -1)
                goto err;
            if (touchtime)
            {
                utimbuf ubuf;
                ubuf.actime = (cast(stat_t*)touchtime).st_atime;
                ubuf.modtime = (cast(stat_t*)touchtime).st_mtime;
                if (utime(name, &ubuf))
                    goto err;
            }
            return 0;
        err2:
            close(fd);
            .remove(name);
        err:
            return 1;
        }
        else version(Windows)
        {
            HANDLE h;
            DWORD numwritten;
            char* name;
            name = this.name.toChars();
            h = CreateFileA(name, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, null);
            if (h == INVALID_HANDLE_VALUE)
                goto err;
            if (WriteFile(h, buffer, len, &numwritten, null) != TRUE)
                goto err2;
            if (len != numwritten)
                goto err2;
            if (touchtime)
            {
                SetFileTime(h, null, null, &(cast(WIN32_FIND_DATAA*)touchtime).ftLastWriteTime);
            }
            if (!CloseHandle(h))
                goto err;
            return 0;
        err2:
            CloseHandle(h);
            DeleteFileA(name);
        err:
            return 1;
        }
        else
        {
            assert(0);
        }
    }

    /*********************************************
     * Append to a file.
     * Returns:
     *      0       success
     */
    extern(C++) int append()
    {
        version(Posix)
        {
            return 1;
        }
        else version(Windows)
        {
            HANDLE h;
            DWORD numwritten;
            char* name;
            name = this.name.toChars();
            h = CreateFileA(name, GENERIC_WRITE, 0, null, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, null);
            if (h == INVALID_HANDLE_VALUE)
                goto err;
            version(all)
            {
                SetFilePointer(h, 0, null, FILE_END);
            }
            else
            {
                // INVALID_SET_FILE_POINTER doesn't seem to have a definition
                if (SetFilePointer(h, 0, null, FILE_END) == INVALID_SET_FILE_POINTER)
                    goto err;
            }
            if (WriteFile(h, buffer, len, &numwritten, null) != TRUE)
                goto err2;
            if (len != numwritten)
                goto err2;
            if (touchtime)
            {
                SetFileTime(h, null, null, &(cast(WIN32_FIND_DATAA*)touchtime).ftLastWriteTime);
            }
            if (!CloseHandle(h))
                goto err;
            return 0;
        err2:
            CloseHandle(h);
        err:
            return 1;
        }
        else
        {
            assert(0);
        }
    }

    /*******************************************
     * Return !=0 if file exists.
     *      0:      file doesn't exist
     *      1:      normal file
     *      2:      directory
     */
    extern(C++) int exists()
    {
        version(Posix)
        {
            return 0;
        }
        else version(Windows)
        {
            DWORD dw;
            int result;
            char* name;
            name = this.name.toChars();
            if (touchtime)
                dw = (cast(WIN32_FIND_DATAA*)touchtime).dwFileAttributes;
            else
                dw = GetFileAttributesA(name);
            if (dw == -1)
                result = 0;
            else if (dw & FILE_ATTRIBUTE_DIRECTORY)
                result = 2;
            else
                result = 1;
            return result;
        }
        else
        {
            assert(0);
        }
    }

    /* Given wildcard filespec, return an array of
     * matching File's.
     */
    extern(C++) static Files* match(char* n)
    {
        return match(new FileName(n));
    }

    extern(C++) static Files* match(FileName* n)
    {
        version(Posix)
        {
            return null;
        }
        else version(Windows)
        {
            HANDLE h;
            WIN32_FIND_DATAA fileinfo;
            auto a = new Files();
            const(char)* c = n.toChars();
            const(char)* name = n.name();
            h = FindFirstFileA(c, &fileinfo);
            if (h != INVALID_HANDLE_VALUE)
            {
                do
                {
                    // Glue path together with name
                    char* fn;
                    File* f;
                    fn = cast(char*)mem.malloc(name - c + strlen(&fileinfo.cFileName[0]) + 1);
                    memcpy(fn, c, name - c);
                    strcpy(fn + (name - c), &fileinfo.cFileName[0]);
                    f = new File(fn);
                    f.touchtime = mem.malloc((WIN32_FIND_DATAA).sizeof);
                    memcpy(f.touchtime, &fileinfo, (fileinfo).sizeof);
                    a.push(f);
                }
                while (FindNextFileA(h, &fileinfo) != FALSE);
                {}
                FindClose(h);
            }
            return a;
        }
        else
        {
            assert(0);
        }
    }

    // Compare file times.
    // Return   <0      this < f
    //          =0      this == f
    //          >0      this > f
    extern(C++) int compareTime(File* f)
    {
        version(Posix)
        {
            return 0;
        }
        else version(Windows)
        {
            if (!touchtime)
                stat();
            if (!f.touchtime)
                f.stat();
            return CompareFileTime(&(cast(WIN32_FIND_DATAA*)touchtime).ftLastWriteTime, &(cast(WIN32_FIND_DATAA*)f.touchtime).ftLastWriteTime);
        }
        else
        {
            assert(0);
        }
    }

    // Read system file statistics
    extern(C++) void stat()
    {
        version(Posix)
        {
            if (!touchtime)
            {
                touchtime = mem.calloc(1, (stat_t).sizeof);
            }
        }
        else version(Windows)
        {
            HANDLE h;
            if (!touchtime)
            {
                touchtime = mem.calloc(1, (WIN32_FIND_DATAA).sizeof);
            }
            h = FindFirstFileA(name.toChars(), cast(WIN32_FIND_DATAA*)touchtime);
            if (h != INVALID_HANDLE_VALUE)
            {
                FindClose(h);
            }
        }
        else
        {
            assert(0);
        }
    }

    /* Set buffer
     */
    extern(C++) void setbuffer(void* buffer, size_t len)
    {
        this.buffer = cast(ubyte*)buffer;
        this.len = len;
    }

    // delete file
    extern(C++) void remove()
    {
        version(Posix)
        {
            int dummy = .remove(this.name.toChars());
        }
        else version(Windows)
        {
            DeleteFileA(this.name.toChars());
        }
        else
        {
            assert(0);
        }
    }

}

