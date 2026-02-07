import placeholderDefs from '../data/placeholders.json';

export type PlaceholderDef = {
  type: string;
  default: string;
  description: string;
  options?: string[];
};

export type FieldGroup = {
  label: string;
  keys: string[];
};

export const FIELD_GROUPS: FieldGroup[] = [
  {
    label: 'Data Center & Scrubbing Centers',
    keys: ['DC_NAME', 'CENTER_1', 'CENTER_2'],
  },
  {
    label: 'Protected Prefixes',
    keys: ['PROTECTED_CIDR_V4', 'PROTECTED_NET_V4', 'PROTECTED_PREFIX_V6', 'PROTECTED_NET_V6'],
  },
  {
    label: 'BGP',
    keys: ['CUSTOMER_ASN', 'F5_XC_ASN', 'BGP_PASSWORD'],
  },
  {
    label: 'XC Scrubbing Center Outer IPs',
    keys: ['XC_C1_OUTER_V4', 'XC_C2_OUTER_V4', 'XC_C1_OUTER_V6', 'XC_C2_OUTER_V6'],
  },
  {
    label: 'BIG-IP Outer Self IPs',
    keys: ['BIGIP_A_OUTER_V4', 'BIGIP_B_OUTER_V4', 'BIGIP_A_OUTER_V6', 'BIGIP_B_OUTER_V6'],
  },
  {
    label: 'Inner IPs — XC Side',
    keys: [
      'XC_C1_T1_INNER_V4', 'XC_C2_T1_INNER_V4', 'XC_C1_T2_INNER_V4', 'XC_C2_T2_INNER_V4',
      'XC_C1_T1_INNER_V6', 'XC_C2_T1_INNER_V6', 'XC_C1_T2_INNER_V6', 'XC_C2_T2_INNER_V6',
    ],
  },
  {
    label: 'Inner IPs — BIG-IP Side',
    keys: [
      'BIGIP_C1_T1_INNER_V4', 'BIGIP_C2_T1_INNER_V4', 'BIGIP_C1_T2_INNER_V4', 'BIGIP_C2_T2_INNER_V4',
      'BIGIP_C1_T1_INNER_V6', 'BIGIP_C2_T1_INNER_V6', 'BIGIP_C1_T2_INNER_V6', 'BIGIP_C2_T2_INNER_V6',
    ],
  },
];

const STORAGE_KEY = 'f5xc-placeholders';

const defs = placeholderDefs as Record<string, PlaceholderDef>;

export { defs as placeholderDefs };

const cidrToMask: Record<string, string> = {
  '/24 (256 IPs)': '255.255.255.0',
  '/23 (512 IPs)': '255.255.254.0',
  '/22 (1024 IPs)': '255.255.252.0',
  '/21 (2048 IPs)': '255.255.248.0',
};

const cidrToShort: Record<string, string> = {
  '/24 (256 IPs)': '/24',
  '/23 (512 IPs)': '/23',
  '/22 (1024 IPs)': '/22',
  '/21 (2048 IPs)': '/21',
};

export function getDefaults(): Record<string, string> {
  const defaults: Record<string, string> = {};
  for (const [key, def] of Object.entries(defs)) {
    defaults[key] = def.default;
  }
  return defaults;
}

export function loadValues(): Record<string, string> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) return JSON.parse(stored);
  } catch { /* ignore */ }
  return getDefaults();
}

export function saveValues(values: Record<string, string>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(values));
}

export function clearValues() {
  localStorage.removeItem(STORAGE_KEY);
}

export function getComputedValues(values: Record<string, string>): Record<string, string> {
  const cidr = values['PROTECTED_CIDR_V4'] || '/24 (256 IPs)';
  const mask = cidrToMask[cidr] || '255.255.255.0';
  const short = cidrToShort[cidr] || '/24';
  const net = values['PROTECTED_NET_V4'] || '192.0.2.0';
  return {
    PROTECTED_MASK_V4: mask,
    PROTECTED_PREFIX_V4: `${net}${short}`,
  };
}

export function getAllValues(values: Record<string, string>): Record<string, string> {
  return { ...values, ...getComputedValues(values) };
}

export function emitChange(values: Record<string, string>) {
  document.dispatchEvent(
    new CustomEvent('placeholder-change', { detail: getAllValues(values) }),
  );
}
