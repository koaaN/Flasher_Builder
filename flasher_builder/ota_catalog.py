"""Daniel Springer's public OTA catalog and session-based temporary link resolver."""
from __future__ import annotations

import http.cookiejar
from datetime import date
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, parse_qs
from urllib.request import Request, build_opener, HTTPCookieProcessor

SITE = 'https://roms.danielspringer.at/index.php?view=ota'
API = 'https://roms.danielspringer.at/api/ota.php'
TTL = 900
MAX_RESPONSE = 16 * 1024 * 1024
DEVICE_NAMES = {
    'Oneplus 13': 'OP 13', 'Oneplus 13R': 'OP 13R', 'Oneplus 13S': 'OP 13S',
    'Oneplus 13T': 'OP 13T', 'Oneplus 15': 'OP 15', 'Oneplus 15R': 'OP 15R',
    'Oneplus 15T': 'OP 15T', 'Oneplus Ace 5': 'OP ACE 5', 'Oneplus Ace 5 Pro': 'OP ACE 5 PRO',
    'Oneplus Ace 6': 'OP ACE 6', 'Oneplus Ace 6T': 'OP ACE 6T',
    'Oneplus Pad 2 Pro': 'OP PAD2 PRO', 'Oneplus Pad 3': 'OP PAD3',
    'Oneplus Pad 3 Pro': 'OP PAD3 PRO', 'Realme GT 7 Pro': 'Realme GT7 PRO',
    'Realme NEO8': 'Realme NEO 8',
    'OPPO Find X9 Ultra': 'OPPO FIND X9 ULTRA',
}


class CatalogError(Exception):
    pass


def targets(device, kind, region):
    if needs_matched_odm(device, kind, region):
        return {'ota': ('OP 15R', region)}
    if device == 'Oneplus Ace 6' and kind == 'SuperHybrid Flasher' and region == 'IN':
        return {'ota': ('OP 15R', 'IN'), 'base': ('OP ACE 6', 'CN')}
    try:
        return {'ota': (DEVICE_NAMES[device], region)}
    except KeyError as e:
        raise CatalogError('This device has no OTA catalog mapping.') from e


def needs_matched_odm(device, kind, region):
    return device == 'Oneplus Ace 6T' and kind == 'Super Flasher' and region in ('IN', 'GLO')


def patch_date(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
        raise CatalogError('A complete security patch date is required to match the ODM source.')
    try:
        date.fromisoformat(value)
    except ValueError as e:
        raise CatalogError('The security patch date is invalid.') from e
    return value


def matching_odm(data, target):
    patch = patch_date(target.get('security_patch'))
    candidates = [e for e in releases_for(data, 'OP ACE 6T', 'CN') if e.get('security_patch') == patch]
    if not candidates:
        raise CatalogError(f'No Ace 6T CN OTA has security patch {patch}. Choose a target with an exact patch match; a different ODM will not be substituted.')
    return candidates[0]


def release_from_metadata(data, device, region, metadata):
    """Identify a local/downloaded target without choosing a newer release."""
    values = '\n'.join(str(metadata.get(k, '')) for k in
                       ('version_name', 'ota_version', 'post-build-incremental', 'post-build'))
    versions = set(re.findall(r'\d+(?:\.\d+){2,4}', values))
    matches = [e for e in releases_for(data, device, region)
               if (e.get('ota_version') and e['ota_version'] in values) or
               (e.get('model') and re.search(r'(?<![A-Za-z0-9])' + re.escape(e['model']) + r'(?![A-Za-z0-9])', values)
                and any(v in versions for v in re.findall(r'\d+(?:\.\d+){2,4}', e['version'])))]
    if len(matches) != 1:
        raise CatalogError('Could not identify this local OTA as an exact OnePlus 15R version for the selected region. Select its version in the catalog or use a matching full OTA.')
    return matches[0]


def request(opener, url, data=None, headers=None):
    req = Request(url, data=urlencode(data).encode() if data is not None else None,
                  headers={'User-Agent': 'FlasherBuilder/1.0', **(headers or {})})
    try:
        with opener.open(req, timeout=35) as response:
            body = response.read(MAX_RESPONSE + 1)
            if len(body) > MAX_RESPONSE:
                raise CatalogError('The OTA service returned an oversized response.')
            return body, response.headers
    except HTTPError as e:
        if e.code == 304:
            return None, e.headers
        raise CatalogError(f'OTA service returned HTTP {e.code}. Try again later.') from e
    except (URLError, OSError, TimeoutError) as e:
        raise CatalogError('Could not reach the OTA service. Check your connection and try again.') from e


def validate_catalog(data):
    if not isinstance(data, dict) or str(data.get('api_version')) != '1' or not isinstance(data.get('releases'), list):
        raise CatalogError('The OTA service returned an unsupported catalog format.')
    ids = set()
    for entry in data['releases']:
        if not isinstance(entry, dict) or not all(isinstance(entry.get(k), str) and entry[k]
                for k in ('id', 'device', 'region', 'version', 'source_url')):
            raise CatalogError('The OTA catalog contains an incomplete release.')
        if entry['id'] in ids or urlsplit(entry['source_url']).scheme not in ('http', 'https'):
            raise CatalogError('The OTA catalog contains an invalid release.')
        ids.add(entry['id'])
    return data


def load_catalog(cache_dir, force=False):
    """Share a 15-minute, ETag-aware cache across GUI and worker processes."""
    path = Path(cache_dir) / 'catalog.json'
    cached = None
    try:
        cached = json.loads(path.read_text(encoding='utf-8'))
        validate_catalog(cached['data'])
        if not force and 0 <= time.time() - cached['fetched_at'] < TTL:
            return cached['data']
    except (OSError, ValueError, KeyError, TypeError, CatalogError):
        cached = None
    headers = {'If-None-Match': cached['etag']} if cached and cached.get('etag') else {}
    try:
        body, response_headers = request(build_opener(), API, headers=headers)
        if body is None:
            if not cached:
                raise CatalogError('The OTA service returned an empty catalog.')
            data = cached['data']
        else:
            try:
                data = validate_catalog(json.loads(body))
            except (ValueError, UnicodeError) as e:
                raise CatalogError('The OTA service returned invalid JSON.') from e
        envelope = {'fetched_at': time.time(), 'etag': response_headers.get('ETag', headers.get('If-None-Match', '')), 'data': data}
        temporary = None
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as f:
                temporary = Path(f.name)
                json.dump(envelope, f)
            os.replace(temporary, path)
        except OSError:
            pass  # A read-only app folder must not prevent catalog use.
        finally:
            if temporary is not None:
                try:
                    temporary.unlink(missing_ok=True)
                except OSError:
                    pass
        return data
    except CatalogError:
        if cached:
            return dict(cached['data'], _stale=True)
        raise


def releases_for(data, device, region):
    def version_key(entry):
        parts = tuple((1, int(p)) if p.isdigit() else (0, p.casefold())
                      for p in re.split(r'(\d+)', entry['version']))
        return bool(entry.get('is_latest')), entry.get('build_timestamp') or '', parts
    return sorted((e for e in data['releases'] if (e['device'], e['region']) == (device, region)),
                  key=version_key, reverse=True)


def find_release(cache_dir, release_id, device, region):
    data = load_catalog(cache_dir)
    matches = [e for e in releases_for(data, device, region) if e['id'] == release_id]
    if not matches:
        raise CatalogError('The selected OTA version is no longer listed for this device/region. Fetch versions again.')
    return matches[0]


class OtaPage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.devices = {}
        self.result = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id') == 'device':
            self.devices = json.loads(attrs.get('data-devices', '{}'))
        elif attrs.get('id') == 'resultBox':
            self.result = attrs


def parse_page(body):
    try:
        page = OtaPage()
        page.feed(body.decode('utf-8'))
        return page
    except (ValueError, UnicodeError) as e:
        raise CatalogError('The OTA website returned an unreadable page.') from e


def usable_link(url):
    parts = urlsplit(url)
    if parts.scheme not in ('https', 'http') or not parts.hostname or parts.path.endswith('/downloadCheck'):
        return False
    query = parse_qs(parts.query)
    for name in ('x-oss-expires', 'Expires', 'expires'):
        if name in query:
            try:
                return float(query[name][0]) > time.time() + 120
            except ValueError:
                return False
    return True


def resolve_link(entry):
    """Never persist signed links. Resolve downloadCheck via the site's own session."""
    source = entry['source_url']
    # Unsigned direct ZIPs need no session. Signed links are refreshed via the site.
    parts = urlsplit(source)
    if parts.path.lower().endswith('.zip') and not any(k in parse_qs(parts.query)
            for k in ('Expires', 'expires', 'x-oss-expires', 'Signature', 'x-oss-signature')) and usable_link(source):
        return source
    opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
    page = parse_page(request(opener, SITE)[0])
    try:
        versions = page.devices[entry['device']][entry['region']]
        index = versions.index(entry['version'])
    except (KeyError, ValueError, TypeError, AttributeError) as e:
        raise CatalogError('This version is no longer available on the OTA website. Fetch versions again.') from e
    result = parse_page(request(opener, SITE, dict(device=entry['device'], region=entry['region'], version_index=index))[0]).result
    url = result.get('data-url', '')
    if result.get('data-link-ready') == '1' and usable_link(url):
        return url
    if result.get('data-ota-key') and result.get('data-csrf'):
        try:
            data = json.loads(request(opener, SITE + '&ota_action=resolve_json',
                    dict(k=result['data-ota-key'], csrf=result['data-csrf']))[0])
        except (ValueError, UnicodeError) as e:
            raise CatalogError('The OTA website returned an invalid link response.') from e
        if data.get('ok') and usable_link(data.get('url', '')):
            return data['url']
    raise CatalogError('The OTA website could not provide a fresh download link. Try another version or retry later.')
