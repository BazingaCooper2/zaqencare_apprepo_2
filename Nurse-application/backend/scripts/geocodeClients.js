require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const GEOCODE_API_URL = `http://localhost:${process.env.PORT || 3000}/api/geocode`;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing Supabase credentials. Please ensure SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are set in .env');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

/**
 * Geocodes a single client and updates the database
 * @param {string|number} clientId 
 * @param {string} fullAddress 
 */
async function geocodeClient(clientId, fullAddress) {
  try {
    const response = await axios.post(GEOCODE_API_URL, { address: fullAddress }, { timeout: 5000 });
    const { latitude, longitude } = response.data;

    if (latitude === undefined || longitude === undefined || latitude === null || longitude === null) {
      throw new Error(`Invalid coords received: ${JSON.stringify(response.data)}`);
    }

    const { error } = await supabase
      .from('client_final')
      .update({ 
        latitude: parseFloat(latitude), 
        longitude: parseFloat(longitude) 
      })
      .eq('id', clientId)
      .is('latitude', null);

    if (error) throw error;

    console.log(`[SUCCESS] ClientID: ${clientId} | Address: ${fullAddress}`);
    return true;
  } catch (error) {
    const errorMsg = error.response ? JSON.stringify(error.response.data) : error.message;
    console.error(`[FAILURE] ClientID: ${clientId} | Address: ${fullAddress} | Error: ${errorMsg}`);
    throw error;
  }
}

/**
 * Background job to process all clients without geocoordinates
 */
async function runGeocodingJob() {
  console.log('[START] Starting background geocoding job...');
  
  const { data: clients, error } = await supabase
    .from('client_final')
    .select('id, full_address')
    .is('latitude', null);

  if (error) {
    console.error(`[CRITICAL] Failed to fetch clients: ${error.message}`);
    return;
  }

  if (!clients || clients.length === 0) {
    console.log('[INFO] No clients found with missing latitude. Job complete.');
    return;
  }

  console.log(`[INFO] Processing ${clients.length} clients...`);

  let successCount = 0;
  let failCount = 0;

  for (const client of clients) {
    // 1. Skip Empty Addresses
    if (!client.full_address || client.full_address.trim() === '') {
      console.log(`[SKIP] clientId: ${client.id} has empty address`);
      continue;
    }

    let attempts = 0;
    let success = false;

    while (attempts < 3 && !success) {
      attempts++;
      try {
        await geocodeClient(client.id, client.full_address);
        success = true;
        successCount++;
      } catch (err) {
        if (attempts < 3) {
          console.log(`[RETRY] ClientID: ${client.id} | Attempt ${attempts} failed. Retrying...`);
          await new Promise(resolve => setTimeout(resolve, 1000));
        } else {
          console.error(`[MAX_RETRIES] ClientID: ${client.id} failed after 3 attempts.`);
          failCount++;
        }
      }
    }

    // 4. Add Delay Between Requests (Rate Limiting)
    await new Promise(res => setTimeout(res, 300));
  }

  console.log(`[SUMMARY] Success: ${successCount} | Failed: ${failCount}`);
  console.log('[DONE] Background geocoding job finished.');
}

// Ensure error handling for the main job
runGeocodingJob().catch(err => {
  console.error(`[FATAL] Job crashed: ${err.message}`);
  process.exit(1);
});
