import { useState, useEffect, useCallback } from 'react';
import {
  FIELD_GROUPS,
  placeholderDefs,
  loadValues,
  saveValues,
  clearValues,
  getDefaults,
  emitChange,
} from '../lib/placeholder-store';

export default function PlaceholderForm() {
  const [values, setValues] = useState<Record<string, string>>(() => loadValues());

  useEffect(() => {
    emitChange(values);
  }, []);

  const handleChange = useCallback((key: string, value: string) => {
    setValues((prev) => {
      const next = { ...prev, [key]: value };
      saveValues(next);
      emitChange(next);
      return next;
    });
  }, []);

  const handleReset = useCallback(() => {
    clearValues();
    const defaults = getDefaults();
    setValues(defaults);
    emitChange(defaults);
  }, []);

  return (
    <details className="ph-form-wrapper">
      <summary>Customize values for this guide</summary>
      <form id="placeholder-form" onSubmit={(e) => e.preventDefault()}>
        {FIELD_GROUPS.map((group) => (
          <fieldset key={group.label}>
            <legend>{group.label}</legend>
            <div className="ph-grid">
              {group.keys.map((key) => {
                const def = placeholderDefs[key];
                if (!def) return null;
                return (
                  <label key={key}>
                    <span className="ph-label">{def.description}</span>
                    {def.type === 'dropdown' && def.options ? (
                      <select
                        value={values[key] ?? def.default}
                        onChange={(e) => handleChange(key, e.target.value)}
                      >
                        {def.options.map((opt) => (
                          <option key={opt} value={opt}>
                            {opt}
                          </option>
                        ))}
                      </select>
                    ) : (
                      <input
                        type="text"
                        value={values[key] ?? def.default}
                        onChange={(e) => handleChange(key, e.target.value)}
                      />
                    )}
                  </label>
                );
              })}
            </div>
          </fieldset>
        ))}
        <button type="button" className="ph-reset" onClick={handleReset}>
          Reset to defaults
        </button>
      </form>
    </details>
  );
}
