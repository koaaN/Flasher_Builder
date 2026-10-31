"""Read small OTA ZIP metadata through checked HTTP ranges, never the payload."""
import io
import re
from urllib.request import Request, urlopen
import zipfile

HEADERS = {'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 16; CPH2653 Build/AP3A.240617.008)',
           'userId': 'oplus-ota|15002017', 'language': 'en-US', 'brand': 'oneplus-exp',
           'Accept-Encoding': 'identity'}


class RangeError(Exception):
    pass


class RangeReader(io.RawIOBase):
    def __init__(self, url, check=lambda: None):
        super().__init__()
        self.url = url; self.check = check; self.position = 0; self.length = None
        self.transferred = 0
        self._range(0, 0)

    def _range(self, start, end):
        self.check()
        size = end - start + 1
        if size > 8 * 1024**2 or self.transferred + size > 16 * 1024**2:
            raise RangeError('Remote OTA metadata exceeds the selective-read limit.')
        request = Request(self.url, headers=HEADERS | {'Range': f'bytes={start}-{end}'})
        with urlopen(request, timeout=20) as response:
            if response.status != 206:
                raise RangeError('The OTA server does not support HTTP ranges. ODM-only download cannot proceed.')
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.headers.get('Content-Range', ''))
            if not match or (int(match[1]), int(match[2])) != (start, end):
                raise RangeError('The OTA server returned an incorrect byte range.')
            length = int(match[3])
            if length <= end or (self.length is not None and self.length != length):
                raise RangeError('The remote OTA changed during metadata verification.')
            self.length = length
            body = response.read(size + 1)
        self.check()
        if len(body) != size:
            raise RangeError('The OTA server returned a truncated byte range.')
        self.transferred += len(body)
        return body

    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        position = offset if whence == io.SEEK_SET else self.position + offset if whence == io.SEEK_CUR else self.length + offset
        if position < 0: raise ValueError('Negative ZIP offset')
        self.position = position
        return position

    def read(self, size=-1):
        if size < 0: size = self.length - self.position
        size = min(size, self.length - self.position)
        if size <= 0: return b''
        body = self._range(self.position, self.position + size - 1)
        self.position += len(body)
        return body


def ota_metadata(url, check=lambda: None):
    with RangeReader(url, check) as reader, zipfile.ZipFile(reader) as archive:
        payload = archive.getinfo('payload.bin')
        if payload.compress_type != zipfile.ZIP_STORED:
            raise RangeError('This OTA compresses payload.bin inside the ZIP and cannot be streamed selectively.')
        info = archive.getinfo('META-INF/com/android/metadata')
        if info.file_size > 1024**2 or info.compress_size > 1024**2:
            raise RangeError('The OTA metadata is too large.')
        fields = dict(line.split('=', 1) for line in archive.read(info).decode('utf-8').splitlines() if '=' in line)
        if fields.get('ota-type', 'AB') != 'AB' or fields.get('pre-build') or fields.get('pre-build-incremental'):
            raise RangeError('The ODM source must be a full AB OTA, not an incremental update.')
        return fields
