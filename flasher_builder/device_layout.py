"""Firmware family and package paths that cannot be inferred from the region."""


def coloros(device, region):
    return device == 'X9U' or region == 'CN'


def template_subtree(device, region):
    return 'cos' if coloros(device, region) else 'oos'


def image_folder(device, region):
    if device == 'X9U':
        return 'OTA_FILES_HERE'
    return 'COS_FILES_HERE' if region == 'CN' else 'OOS_FILES_HERE'
