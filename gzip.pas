{*******************************************************************************

                              PSP/PWU  GZIP
                  
********************************************************************************


  Simplified ZLib API for use in PSP programs.                                

  See the Pascal Server Pages Documentation for more information.             
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
    Written by Vladimir Sibirov a.k.a. Trustmaster                            
    http://www.psp.furtopia.org                                               
    mailto:psp@furtopia.org                                                   
    
--------------------------------------------------------------------------------
 Copyright (c) 2003-2005 by Pascal Server Pages development team.            
 See the Pascal Server Pages License for more information.                   
--------------------------------------------------------------------------------

 PSP 1.6.x
 ---------
  [04/MAR/2006 - L505]:
  - changed uses to /zlib/ directory

 PSP 1.4.1
 ---------
  [25.09.05 - Trustmaster]:
  - some memory fixes in gzip_decompress.                                     

  [21.09.05 - Trustmaster]:
  - added support for unknown size decompression;                             
  - optimized gzip_gzbuffer.                                                  

  [17.09.05 - Trustmaster]:
  - First implementation of this unit. The only problem unfixed is that when  
  calling pack and then unpack, first succeeds and second fails with access   
  violation on gzopen call. Looks like memory leak/bug in paszlib itself.     

*******************************************************************************}

{$IFDEF FPC}{$MODE OBJFPC}{$H+}
   {$IFDEF EXTRA_SECURE}
    {$R+}{$Q+}{$CHECKPOINTER ON}
   {$ENDIF}
{$ENDIF}

unit gzip;


interface


function GZCompress(const source: string): string;
function GZDecompress(const source: string; dest_len: longword): string;
function GZBufferPack(const source: string): string;
function GZPack(const source, dest: string): boolean;
function GZUnpack(const source, dest: string): boolean;


implementation

uses 
  zlib_zutil,
  zlib_zbase,
  zlib_gzcrc,
  zlib_gzio,
  zlib_zdeflate,
  zlib_zcompres,
  zlib_zuncompr;
                                   

const   GZIP_BUFF_LEN = 16384;
    // Buffer length

type    GZBuff = packed array[0..GZIP_BUFF_LEN - 1] of byte;
    // Buffer


// GZIP data compression
function GZCompress(const source: string): string;
var tmp, stmp: pBytef;
    slen, dlen: uLong;
    i: longword;
begin
    // Init
    result := '';
    slen := length(source);
    dlen := slen + (slen div 100) + 12; // That should be enough
    tmp := getmem(dlen);
    // Translating AnsiString into pBytef
    stmp := getmem(slen + 1);
    for i := 1 to slen do
        begin
            stmp^ := ord(source[i]);
            inc(stmp);
        end;
    stmp^ := 0;
    stmp := stmp - slen;
    // Compress
    compress(tmp, dlen, stmp, slen);
    // Translating pBytef to AnsiString
    SetLength(result, dlen);
    for i := 1 to dlen do
        begin
            result[i] := chr(tmp^);
            inc(tmp);
        end;
    tmp := tmp - dlen;
    freemem(stmp);
    freemem(tmp);
end;


// GZIP data decompression
function GZDecompress(const source: string; dest_len: longword): string;
var tmp, stmp: pBytef;
    slen, dlen: uLong;
    i: longword;
    err: int;
begin
    // Init
    result := '';
    dlen := dest_len;
    slen := length(source);
    // Translating AnsiString into pBytef
    stmp := getmem(slen + 1);
    for i := 1 to slen do
        begin
            stmp^ := ord(source[i]);
            inc(stmp);
        end;
    stmp^ := 0;
    stmp := stmp - slen;
    // Assuming dest_len if zero
    if dlen = 0 then dlen := slen * 2;
    tmp := getmem(dlen);
    // Decompress
    repeat
        err := uncompress(tmp, dlen, stmp, slen);
        case err of
            Z_OK: break;
            Z_BUF_ERROR: if dlen < (slen * 256) then
                begin
                    dlen := dlen * 2;
                    freemem(tmp);
                    tmp := getmem(dlen);
                end
                else
                begin
                    // Expanding limits
                    freemem(tmp);
                    freemem(stmp);
                    exit('');
                end;
            Z_MEM_ERROR, Z_STREAM_ERROR:
                begin
                    freemem(tmp);
                    freemem(stmp);
                    exit('');
                end;
        end;
    until err = Z_OK;
    // Translating pBytef to AnsiString
    SetLength(result, dlen);
    for i := 1 to dlen do
        begin
            result[i] := chr(tmp^);
            inc(tmp);
        end;
    tmp := tmp - dlen;
    freemem(stmp);
    freemem(tmp);
end;


// Packs string buffer and returns string containing data in GZIP format
function GZBufferPack(const source: string): string;
var i, crc, dlen, slen, x: longword;
    err: longint;
    gzheader : array [0..9] of byte;
    tmp, stmp: pBytef;
    s: z_stream;
    c: byte;
begin
    // Init
    result := '';
    slen := length(source);
    dlen := slen + (slen div 100) + 12; // That should be enough
    tmp := getmem(dlen);
    // Translating AnsiString into pBytef
    stmp := getmem(slen + 1);
    for i := 1 to slen do
        begin
            stmp^ := ord(source[i]);
            inc(stmp);
        end;
    stmp^ := 0;
    stmp := stmp - slen;
    // Initializing stream
    s.zalloc := nil;
    s.zfree := nil;
    s.opaque := nil; 
    s.next_in := stmp;
    s.avail_in := uInt(slen);
    s.next_out := tmp;
    s.avail_out := uInt(dlen);
    gzheader[0] := $1F;
    gzheader[1] := $8B;
    gzheader[2] := Z_DEFLATED;
    gzheader[3] := 0;
    gzheader[4] := 0;
    gzheader[5] := 0;
    gzheader[6] := 0;
    gzheader[7] := 0;
    gzheader[8] := 0;
    gzheader[9] := {$IFDEF WIN32}0{$ELSE}3{$ENDIF};
    // Entire deflation
    err := deflateInit2(s, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY);
    if err <> 0 then exit;
    err := deflate(s, Z_FINISH);
    if err <> Z_STREAM_END then exit('');
    if s.total_in <> slen then exit('');
    dlen := s.total_out;
    err := deflateEnd(s);
    // Get CRC32
    crc := crc32(0, Z_NULL, 0);
    crc := crc32(crc, stmp, slen);
    x := crc;
    // Write header to result stream
    for i := 0 to 9 do
    begin
         SetLength(result, length(result) + 1);
         result[length(result)] := chr(gzheader[i]);
    end;
    // Write buffer to result stream
    for i := 0 to dlen - 1 do
    begin
         SetLength(result, length(result) + 1);
         result[length(result)] := chr(tmp^);
         inc(tmp);
    end;
    tmp := tmp - dlen;
    // Write CRC32 and ISIZE in LSB order
    for i := 0 to 3 do
    begin
         c := x and $FF;
         SetLength(result, length(result) + 1);
         result[length(result)] := chr(c);
         x := x shr 8;
    end;
    x := slen;
    for i := 0 to 3 do
    begin
         c := x and $FF;
         SetLength(result, length(result) + 1);
         result[length(result)] := chr(c);
         x := x shr 8;
    end;
    // Free the memory
    freemem(tmp);
    freemem(stmp);
end;



// GZIP file compression
function GZPack(const source, dest: string): boolean;
var sh: file;
    dh: gzFile;
    bf: GZBuff;
    len: uInt;
begin
    // Initializing
    result := false;
    len := 0;
    // Opening handles
    {$I-}
    assign(sh, source);
    reset(sh, 1);
    {$I+}
    if ioresult <> 0 then exit(false);
    dh := gzopen(dest, 'w');
    if dh = nil then
        begin
            close(sh);
            exit(false);
        end;
    // Performing gzip
    repeat
        {$I-}
        blockread(sh, bf, GZIP_BUFF_LEN, len);
        {$I+}
        if ioresult <> 0 then
            begin
                close(sh);
                gzclose(dh);
                exit(false);
            end;
        if len = 0 then break;
        if gzwrite(dh, @bf, len) <> longint(len) then
            begin
                close(sh);
                gzclose(dh);
                exit(false);
            end;
    until len = 0;
    // Done
    close(sh);
    if gzclose(dh) = 0 then result := true;
end;


// GZIP file decompression
function GZUnpack(const source, dest: string): boolean;
var sh: gzFile;
    dh: file;
    bf: GZBuff;
    len: int;
    wlen: uInt;
begin
    // Initialization
    result := false;
    len := 0;
    wlen := 0;
    // Opening
    {$I-}
    assign(dh, dest);
    rewrite(dh, 1);
    {$I+}
    if ioresult <> 0 then exit(false);
    sh := gzopen(source, 'r');
    if sh = nil then
        begin
            close(dh);
            exit(false);
        end;
    // Performing gunzip
    repeat
        len := gzread(sh, @bf, GZIP_BUFF_LEN);
        if len < 0 then
            begin
                close(dh);
                gzclose(sh);
                exit(false);
            end;
        if len = 0 then break;
        {$I-}
        blockwrite(dh, bf, len, wlen);
        {$I+}
        if len <> longint(wlen) then
            begin
                close(dh);
                gzclose(sh);
                exit(false);
            end;
    until len = 0;
    // Done
    close(dh);
    if gzclose(sh) = 0 then result := true;
end;



end.            
