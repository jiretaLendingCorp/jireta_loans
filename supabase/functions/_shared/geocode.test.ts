// supabase/functions/_shared/geocode.test.ts
//
// Coverage para sa server-side geocoding ng TEXT-ONLY na `addresses`.
//
// Ang mahalagang behavior na dapat hindi mag-break:
//   * `buildAddressQuery` — sapat na ba ang address para i-geocode? (street-only
//     = walang saysay na centroid → null, kaya walang maling pin)
//   * `pickBestResult` / `toGeocodeResult` — tanggihan ang (0,0)/out-of-range
//     na coords, at unahin ang street-level na result
//   * `parseGeocodeResponse` — `OK` lang ang may result; ang `ZERO_RESULTS` /
//     `REQUEST_DENIED` ay hindi error na nag-crash, null lang
//   * `googleGeocodingKey` — hindi dapat gamitin ang placeholder/missing key
import {
  assert,
  assertEquals,
  assertFalse,
} from 'https://deno.land/std@0.168.0/testing/asserts.ts';
import {
  buildAddressQuery,
  googleGeocodingKey,
  parseGeocodeResponse,
  pickBestResult,
  toGeocodeResult,
} from './geocode.ts';

// Ang std@0.168 na asserts ay walang `assertNull` — maliit na helper lang.
function assertNull(value: unknown, msg?: string): void {
  assertEquals(value, null, msg);
}

// Ang aktwal na na-save na address ng isang lender na walang pin
// (mula sa production payload ng ci-view/collections-view).
const LENDER_ADDRESS = {
  street: '# 42, Purok 1',
  barangay: 'NAGUILAYAN',
  city: 'SAN CARLOS CITY',
  province: 'PANGASINAN',
  zip_code: null,
};

Deno.test('buildAddressQuery: structured address + Philippines', () => {
  assertEquals(
    buildAddressQuery(LENDER_ADDRESS),
    '# 42, Purok 1, NAGUILAYAN, SAN CARLOS CITY, PANGASINAN, Philippines',
  );
});

Deno.test('buildAddressQuery: kasama ang zip code kapag meron', () => {
  assertEquals(
    buildAddressQuery({ ...LENDER_ADDRESS, zip_code: '2420' }),
    '# 42, Purok 1, NAGUILAYAN, SAN CARLOS CITY, PANGASINAN, 2420, Philippines',
  );
});

Deno.test('buildAddressQuery: walang doble (dedupe) at trimmed ang parts', () => {
  assertEquals(
    buildAddressQuery({
      street: '  Purok 1 ',
      barangay: 'NAGUILAYAN',
      city: 'NAGUILAYAN',
      province: 'PANGASINAN',
    }),
    'Purok 1, NAGUILAYAN, PANGASINAN, Philippines',
  );
});

Deno.test('buildAddressQuery: null kapag kulang sa isang bahagi', () => {
  // Street-only ("Purok 1") ay nagbibigay ng malayong centroid — mas mabuting
  // walang pin kaysa maling pin.
  assertNull(buildAddressQuery({ street: 'Purok 1' }));
  assertNull(buildAddressQuery({}));
  assertNull(buildAddressQuery({ street: '   ', barangay: '  ' }));
  assertNull(buildAddressQuery({ province: null, city: null }));
});

Deno.test('toGeocodeResult: tinatanggap ang valid na coords', () => {
  const result = toGeocodeResult({
    formatted_address: 'Naguilayan, San Carlos City, Pangasinan, Philippines',
    geometry: {
      location: { lat: 15.9281, lng: 120.3489 },
      location_type: 'APPROXIMATE',
    },
  });
  assert(result !== null);
  assertEquals(result!.latitude, 15.9281);
  assertEquals(result!.longitude, 120.3489);
  assertEquals(result!.locationType, 'APPROXIMATE');
  assertFalse(result!.partialMatch);
});

Deno.test('toGeocodeResult: tinatanggihan ang walang saysay na coords', () => {
  // Kulang ang geometry
  assertNull(toGeocodeResult({ formatted_address: 'x' }));
  assertNull(toGeocodeResult({ geometry: { location: { lat: 15.9 } } }));
  // Null Island (0,0) = "walang data" na sagot, hindi tunay na lugar
  assertNull(toGeocodeResult({ geometry: { location: { lat: 0, lng: 0 } } }));
  // Labas sa CHECK constraints ng `addresses` table
  assertNull(toGeocodeResult({ geometry: { location: { lat: 91, lng: 120 } } }));
  assertNull(toGeocodeResult({ geometry: { location: { lat: 15, lng: 181 } } }));
  // NaN / Infinity (bug sa JSON parsing)
  assertNull(toGeocodeResult({ geometry: { location: { lat: NaN, lng: 120 } } }));
});

Deno.test('pickBestResult: inuuna ang street-level at exact na match', () => {
  const result = pickBestResult([
    {
      formatted_address: 'Pangasinan, Philippines',
      geometry: { location: { lat: 15.9, lng: 120.3 }, location_type: 'APPROXIMATE' },
    },
    {
      formatted_address: '# 42, Purok 1, Naguilayan, San Carlos City, Philippines',
      geometry: { location: { lat: 15.9281, lng: 120.3489 }, location_type: 'RANGE_INTERPOLATED' },
    },
  ]);
  assert(result !== null);
  assertEquals(result!.locationType, 'RANGE_INTERPOLATED');
  assertEquals(result!.latitude, 15.9281);
});

Deno.test('pickBestResult: hindi pumipili ng partial_match kung may exact', () => {
  const result = pickBestResult([
    {
      formatted_address: 'Partial, Philippines',
      partial_match: true,
      geometry: { location: { lat: 16.0, lng: 120.5 }, location_type: 'ROOFTOP' },
    },
    {
      formatted_address: 'Exact, Philippines',
      geometry: { location: { lat: 15.5, lng: 120.9 }, location_type: 'GEOMETRIC_CENTER' },
    },
  ]);
  assertEquals(result!.formattedAddress, 'Exact, Philippines');
});

Deno.test('pickBestResult: fallback sa partial_match kapag iyon lang ang meron', () => {
  const result = pickBestResult([
    {
      formatted_address: 'Partial, Philippines',
      partial_match: true,
      geometry: { location: { lat: 16.0, lng: 120.5 }, location_type: 'APPROXIMATE' },
    },
  ]);
  assert(result !== null);
  assert(result!.partialMatch);
  assertEquals(result!.latitude, 16.0);
});

Deno.test('pickBestResult: null kapag walang valid na kandidato', () => {
  assertNull(pickBestResult([]));
  assertNull(pickBestResult(undefined));
  assertNull(pickBestResult([{ geometry: { location: { lat: 0, lng: 0 } } }]));
});

Deno.test('parseGeocodeResponse: OK lang ang may result', () => {
  const ok = parseGeocodeResponse({
    status: 'OK',
    results: [
      {
        formatted_address: 'Naguilayan, San Carlos City, Pangasinan, Philippines',
        geometry: { location: { lat: 15.9281, lng: 120.3489 }, location_type: 'APPROXIMATE' },
      },
    ],
  });
  assertEquals(ok.status, 'OK');
  assert(ok.result !== null);

  const zero = parseGeocodeResponse({ status: 'ZERO_RESULTS', results: [] });
  assertNull(zero.result);
  assertEquals(zero.status, 'ZERO_RESULTS');

  const denied = parseGeocodeResponse({
    status: 'REQUEST_DENIED',
    error_message: 'API keys with referer restrictions cannot be used with this API.',
  });
  assertNull(denied.result);
  assertEquals(denied.status, 'REQUEST_DENIED');
  assert(denied.error!.includes('referer'));

  // Hindi dapat mag-crash kapag blangko ang sagot
  assertNull(parseGeocodeResponse(null).result);
  assertEquals(parseGeocodeResponse(undefined).status, 'UNKNOWN_STATUS');
});

Deno.test('googleGeocodingKey: placeholder at kulang na key ay tinatanggihan', () => {
  const saved = {
    geo: Deno.env.get('GOOGLE_GEOCODING_API_KEY'),
    maps: Deno.env.get('GOOGLE_MAPS_API_KEY'),
  };
  try {
    Deno.env.delete('GOOGLE_GEOCODING_API_KEY');
    Deno.env.delete('GOOGLE_MAPS_API_KEY');
    assertNull(googleGeocodingKey());

    Deno.env.set('GOOGLE_MAPS_API_KEY', 'your-google-maps-key');
    assertNull(googleGeocodingKey());

    Deno.env.set('GOOGLE_MAPS_API_KEY', 'AIzaSyAx7tSEXd23Osn6k-Hqvpm86JF6vVqXHQc');
    assertEquals(
      googleGeocodingKey(),
      'AIzaSyAx7tSEXd23Osn6k-Hqvpm86JF6vVqXHQc',
    );

    // GOOGLE_GEOCODING_API_KEY (dedicated, walang browser restriction) ang
    // mas priority kaysa sa Maps key.
    Deno.env.set('GOOGLE_GEOCODING_API_KEY', 'AIzaDedicatedGeocodingKey');
    assertEquals(googleGeocodingKey(), 'AIzaDedicatedGeocodingKey');
  } finally {
    for (const [name, value] of [
      ['GOOGLE_GEOCODING_API_KEY', saved.geo],
      ['GOOGLE_MAPS_API_KEY', saved.maps],
    ] as const) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});
