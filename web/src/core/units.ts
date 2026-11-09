// Mirror of PulseCore UnitConverter.
export function convert(value: number, from: string, to: string): number | undefined {
  const u = from.trim();
  switch (to) {
    case 'count': return u === 'count' || u === '' ? value : undefined;
    case 'stage': case 'event': return value;
    case 'kcal': return ({ kcal: value, Cal: value, Kcal: value, cal: value / 1000, kJ: value / 4.184, J: value / 4184 } as Record<string, number>)[u];
    case 'm': return ({ m: value, km: value * 1000, cm: value / 100, mm: value / 1000, mi: value * 1609.344, yd: value * 0.9144, ft: value * 0.3048, in: value * 0.0254 } as Record<string, number>)[u];
    case 'cm': return ({ cm: value, m: value * 100, mm: value / 10, in: value * 2.54, ft: value * 30.48 } as Record<string, number>)[u];
    case 'min': return ({ min: value, s: value / 60, hr: value * 60, h: value * 60, ms: value / 60_000 } as Record<string, number>)[u];
    case 's': return ({ s: value, min: value * 60, ms: value / 1000 } as Record<string, number>)[u];
    case 'count/min': return ({ 'count/min': value, bpm: value, '/min': value, 'count/s': value * 60 } as Record<string, number>)[u];
    case 'ms': return ({ ms: value, s: value * 1000 } as Record<string, number>)[u];
    case '%': return u === '%' ? value * 100 : undefined;
    case 'mmHg': return ({ mmHg: value, kPa: value * 7.50062 } as Record<string, number>)[u];
    case 'mL/(kg·min)': return ['mL/min·kg', 'ml/(kg*min)', 'mL/(kg·min)', 'ml/kg*min', 'mL/kg/min', 'ml/min·kg'].includes(u) ? value : undefined;
    case 'kg': return ({ kg: value, g: value / 1000, lb: value * 0.45359237, st: value * 6.35029318, oz: value * 0.028349523125 } as Record<string, number>)[u];
    case 'g': return ({ g: value, kg: value * 1000, mg: value / 1000, mcg: value / 1e6, 'µg': value / 1e6, oz: value * 28.349523125 } as Record<string, number>)[u];
    case 'mg': return ({ mg: value, g: value * 1000, mcg: value / 1000, 'µg': value / 1000 } as Record<string, number>)[u];
    case 'mL': return ({ mL: value, ml: value, L: value * 1000, l: value * 1000, fl_oz_us: value * 29.5735295625, fl_oz_US: value * 29.5735295625, fl_oz_imp: value * 28.4130625, cup_us: value * 236.5882365, cup_US: value * 236.5882365 } as Record<string, number>)[u];
    case 'degC': return ({ degC: value, degF: (value - 32) * 5 / 9, K: value - 273.15 } as Record<string, number>)[u];
    case 'dBASPL': return u === 'dBASPL' ? value : undefined;
    case 'm/s': return ({ 'm/s': value, 'km/hr': value / 3.6, 'km/h': value / 3.6, 'mi/hr': value * 0.44704, mph: value * 0.44704 } as Record<string, number>)[u];
    case 'W': return u === 'W' ? value : undefined;
    case 'kcal/(kg·hr)': return ['kcal/hr·kg', 'kcal/(kg·hr)', 'kcal/(kg*hr)', 'kcal/hr*kg'].includes(u) ? value : undefined;
    case 'mg/dL': return ({ 'mg/dL': value, 'mmol<180.15588000005408>/L': value * 18.0156, 'mmol/L': value * 18.0156 } as Record<string, number>)[u];
    default: return undefined;
  }
}

export const UNIT_SYMBOL: Record<string, string> = {
  count: '', kcal: 'kcal', m: 'm', cm: 'cm', min: 'min', s: 's', 'count/min': 'bpm', ms: 'ms', '%': '%', mmHg: 'mmHg',
  'mL/(kg·min)': 'mL/kg/min', kg: 'kg', g: 'g', mg: 'mg', mL: 'mL', degC: '°C', dBASPL: 'dB', 'm/s': 'm/s', W: 'W',
  'kcal/(kg·hr)': 'MET', 'mg/dL': 'mg/dL', stage: '', event: '',
};
