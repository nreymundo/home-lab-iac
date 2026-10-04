const baseUrl = new URL(process.env.BOOKORBIT_API_URL ?? 'http://bookorbit.media.svc.cluster.local:3000');
const bootstrap = {
  username: process.env.BOOTSTRAP_USERNAME,
  name: process.env.BOOTSTRAP_NAME,
  email: process.env.BOOTSTRAP_EMAIL,
  password: process.env.BOOTSTRAP_PASSWORD,
};
const required = [
  ...Object.values(bootstrap),
  process.env.SETUP_BOOTSTRAP_TOKEN,
  process.env.OIDC_ISSUER_URI,
  process.env.OIDC_CLIENT_ID,
  process.env.OIDC_CLIENT_SECRET,
  process.env.PROWLARR_URL,
  process.env.PROWLARR_API_KEY,
  process.env.HARDCOVER_API_KEY,
  process.env.HARDCOVER_BOOKORBIT_USERNAME,
  process.env.COMICVINE_API_KEY,
  process.env.SMTP_HOST,
  process.env.SMTP_PORT,
  process.env.SMTP_FROM_ADDRESS,
  process.env.SMTP_USERNAME,
  process.env.SMTP_PASSWORD,
];
if (required.some((value) => !value)) throw new Error('Required reconciliation configuration is missing');

const adminPermissions = [
  'library_download',
  'library_upload',
  'library_edit_metadata',
  'library_delete_books',
  'book_dock_access',
  'book_request_access',
  'podcast_manage_feeds',
  'podcast_download',
  'podcast_edit_metadata',
  'podcast_manage_retention',
  'podcast_purge',
  'kobo_sync',
  'koreader_sync',
  'hardcover_sync',
  'readwise_sync',
  'storygraph_sync',
  'opds_access',
  'email_send',
  'manage_email',
  'manage_libraries',
  'manage_metadata_config',
  'manage_icons',
  'manage_app_settings',
  'manage_book_dock',
  'manage_book_requests',
  'book_request_auto_approve',
  'book_request_self_fulfill',
  'manage_users',
  'view_user_activity',
  'view_audit_log',
  'notification_access',
];
const userPermissions = ['library_download', 'opds_access', 'email_send'];
const desiredMappings = new Map([
  ...adminPermissions.map((permission) => [`bookorbit-admin:${permission}`, permission]),
  ...userPermissions.map((permission) => [`bookorbit-user:${permission}`, permission]),
]);

async function request(
  path,
  { method = 'GET', token, headers = {}, body, expected = [200], expectJson = true } = {},
) {
  let response;
  try {
    response = await fetch(new URL(`/api/v1${path}`, baseUrl), {
      method,
      headers: {
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...headers,
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    throw new Error(`BookOrbit API request failed (${method} ${path})`);
  }
  if (!expected.includes(response.status)) {
    throw new Error(`BookOrbit API returned HTTP ${response.status} (${method} ${path})`);
  }
  if (response.status === 204 || !expectJson) return undefined;
  try {
    return await response.json();
  } catch {
    throw new Error(`BookOrbit API returned invalid JSON (${method} ${path})`);
  }
}

async function waitForHealth() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(new URL('/api/v1/health', baseUrl), { signal: AbortSignal.timeout(5_000) });
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
  throw new Error('BookOrbit health endpoint did not become ready');
}

async function ensureBootstrap() {
  const status = await request('/auth/setup-status');
  if (!status.needsSetup) return;
  try {
    await request('/auth/setup', {
      method: 'POST',
      headers: { 'x-setup-token': process.env.SETUP_BOOTSTRAP_TOKEN },
      body: bootstrap,
      expected: [201],
    });
  } catch (error) {
    const afterRace = await request('/auth/setup-status');
    if (afterRace.needsSetup) throw error;
  }
}

async function authenticate() {
  const result = await request('/auth/login', {
    method: 'POST',
    body: { username: bootstrap.username, password: bootstrap.password },
  });
  if (!result.accessToken) throw new Error('BookOrbit local API login returned no access token');
  return result.accessToken;
}

async function reconcileProvider(token) {
  const slug = 'authentik';
  const providers = await request('/app-settings/oidc/providers', { token });
  const provider = {
    displayName: 'Authentik',
    iconUrl: 'https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/svg/authentik.svg',
    enabled: true,
    issuerUri: process.env.OIDC_ISSUER_URI,
    clientId: process.env.OIDC_CLIENT_ID,
    clientSecret: process.env.OIDC_CLIENT_SECRET,
    scopes: 'openid email profile bookorbit',
    claimMapping: {
      username: 'preferred_username',
      name: 'name',
      email: 'email',
      groups: 'groups',
    },
    autoProvision: {
      enabled: true,
      // Authentik is the sole trusted issuer; linking matches its preferred_username,
      // not an arbitrary email address. Local self-registration is disabled below.
      allowLocalLinking: true,
      defaultPermissionNames: [],
    },
  };
  const existing = providers.find((entry) => entry.slug === slug);
  if (existing) {
    await request(`/app-settings/oidc/providers/${slug}`, { method: 'PUT', token, body: provider });
  } else {
    await request('/app-settings/oidc/providers', {
      method: 'POST',
      token,
      body: { slug, ...provider },
      expected: [201],
    });
  }

  const mappingsPath = `/app-settings/oidc/providers/${slug}/group-mappings`;
  const existingMappings = await request(mappingsPath, { token });
  const mappingsByClaim = new Map(existingMappings.map((mapping) => [mapping.oidcGroupClaim, mapping]));
  for (const [oidcGroupClaim, permissionName] of desiredMappings) {
    const mapping = mappingsByClaim.get(oidcGroupClaim);
    if (!mapping) {
      await request(mappingsPath, {
        method: 'POST',
        token,
        body: { oidcGroupClaim, permissionName },
        expected: [201],
      });
    } else if (mapping.permissionName !== permissionName) {
      await request(`${mappingsPath}/${mapping.id}`, {
        method: 'PUT',
        token,
        body: { permissionName },
      });
    }
  }
  for (const mapping of existingMappings) {
    if (mapping.oidcGroupClaim.startsWith('bookorbit-admin:') || mapping.oidcGroupClaim.startsWith('bookorbit-user:')) {
      if (!desiredMappings.has(mapping.oidcGroupClaim)) {
        await request(`${mappingsPath}/${mapping.id}`, { method: 'DELETE', token, expected: [204] });
      }
    }
  }
}

async function ensureLibraries(token) {
  const libraries = await request('/libraries', { token });
  const desired = [
    { name: 'Comics', icon: 'book-open', path: '/nas/library/comics', organizationMode: 'book_per_file' },
    { name: 'Books', icon: 'book', path: '/nas/library/books', organizationMode: 'book_per_folder' },
    { name: 'Audiobooks', icon: 'headphones', path: '/nas/library/audiobooks', organizationMode: 'book_per_folder' },
  ];
  const autoScanCronExpression = '0 0 * * *';
  const managed = [];
  for (const { name, icon, path, organizationMode } of desired) {
    let existing = libraries.find((library) => library.name.toLowerCase() === name.toLowerCase());
    if (!existing) {
      managed.push(await request('/libraries', {
        method: 'POST',
        token,
        body: {
          type: 'books',
          name,
          icon,
          folders: [path],
          organizationMode,
          watch: false,
          autoScanCronExpression,
        },
        expected: [201],
      }));
      continue;
    }
    const folders = (existing.folders ?? []).map((folder) => folder.path);
    if (folders.length !== 1 || folders[0] !== path || existing.organizationMode !== organizationMode) {
      throw new Error(`An existing ${name} library has a different folder or organization mode; refusing to modify it`);
    }
    if (existing.autoScanCronExpression !== autoScanCronExpression) {
      existing = await request(`/libraries/${existing.id}`, {
        method: 'PATCH',
        token,
        body: { autoScanCronExpression },
      });
    }
    managed.push(existing);
  }
  // This list is authoritative: deleting other libraries also removes their
  // catalog data (and downloaded media for podcast libraries) through BookOrbit.
  const managedIds = new Set(managed.map((library) => library.id));
  for (const library of libraries) {
    if (!managedIds.has(library.id)) {
      await request(`/libraries/${library.id}`, { method: 'DELETE', token, expected: [204] });
    }
  }
  return managed;
}

async function reconcileLibraryAccess(token, library) {
  const defaults = await request('/app-settings/default-library-access', { token });
  if (!defaults.libraryIds.includes(library.id)) {
    await request('/app-settings/default-library-access', {
      method: 'PUT',
      token,
      body: { libraryIds: [...defaults.libraryIds, library.id] },
    });
  }

  const accessPath = `/libraries/${library.id}/access`;
  const access = await request(accessPath, { token });
  const accessByUser = new Map(access.map((entry) => [entry.userId, entry.accessLevel]));
  const pageSize = 100;
  for (let page = 0; ; page += 1) {
    const result = await request(`/users?page=${page}&pageSize=${pageSize}&provisioningMethod=oidc`, { token });
    for (const user of result.users) {
      const level = !user.active
        ? undefined
        : user.permissions.includes('manage_libraries')
          ? 'editor'
          : user.permissions.includes('library_download')
            ? 'viewer'
            : undefined;
      const current = accessByUser.get(user.id);
      if (!level && current) {
        await request(`${accessPath}/${user.id}`, { method: 'DELETE', token, expected: [204] });
      } else if (level && level !== current) {
        await request(accessPath, {
          method: 'POST',
          token,
          body: { userId: user.id, accessLevel: level },
          expected: [201],
          expectJson: false,
        });
      }
    }
    if ((page * pageSize) + result.users.length >= result.total) break;
  }
}

async function reconcileProwlarr(token) {
  const path = '/admin/request-indexer-managers';
  const { managers } = await request(path, { token });
  const configuration = {
    name: 'Prowlarr',
    enabled: true,
    baseUrl: process.env.PROWLARR_URL,
    credential: process.env.PROWLARR_API_KEY,
    allowPrivateAddress: true,
    syncNewIndexers: true,
  };
  const existing = managers.find((manager) => manager.name.toLowerCase() === 'prowlarr');
  const manager = existing
    ? await request(`${path}/${existing.id}`, { method: 'PUT', token, body: configuration })
    : await request(path, {
      method: 'POST',
      token,
      body: { type: 'prowlarr', ...configuration },
      expected: [201],
    });
  // Create/update attempts a sync but suppresses failures; this explicit sync
  // makes an unreachable manager or invalid key fail the reconciliation job.
  await request(`${path}/${manager.id}/sync`, { method: 'POST', token });
}

async function reconcileMetadataAndHardcover(token) {
  // Personal settings belong to the authenticated user, not an admin-selected ID.
  const user = await request('/auth/me', { token });
  if (user.username !== process.env.HARDCOVER_BOOKORBIT_USERNAME) {
    throw new Error('Hardcover target does not match the authenticated BookOrbit account; refusing to configure it');
  }
  const apiKey = process.env.HARDCOVER_API_KEY;
  const validation = await request('/hardcover/validate-token', {
    method: 'POST',
    token,
    body: { token: apiKey },
    expected: [201],
  });
  if (!validation.valid) throw new Error('Hardcover API token validation failed');
  // The metadata API merges this patch, preserving unlisted providers and fields.
  await request('/metadata-preferences/providers', {
    method: 'PUT',
    token,
    body: {
      hardcover: { enabled: true, apiKey },
      kobo: { enabled: true, country: 'us', language: 'en' },
      audible: { enabled: true },
      audnexus: { enabled: true },
      librofm: { enabled: true },
      comicvine: { enabled: true, apiKey: process.env.COMICVINE_API_KEY },
      ranobedb: { enabled: true },
    },
  });
  // Keep book-selection scope unchanged; enable public auto-sync without running sync/import.
  await request('/hardcover/settings', {
    method: 'PATCH',
    token,
    body: {
      apiToken: apiKey,
      enabled: true,
      autoSyncOnStatusChange: true,
      autoSyncOnProgressUpdate: true,
      autoSyncOnRatingChange: true,
      privacySettingId: 1,
    },
  });
}

async function reconcileEmail(token) {
  // Roll out the app's EMAIL_ENCRYPTION_KEY before provisioning SMTP passwords.
  const path = '/email/providers';
  const providers = await request(path, { token });
  const configuration = {
    name: 'Purelymail',
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT),
    username: process.env.SMTP_USERNAME,
    password: process.env.SMTP_PASSWORD,
    fromName: 'BookOrbit',
    fromAddress: process.env.SMTP_FROM_ADDRESS,
    auth: true,
    ssl: false,
    startTls: true,
    tlsRejectUnauthorized: true,
  };
  const existing = providers.find((provider) => provider.name === configuration.name);
  let provider = existing
    ? await request(`${path}/${existing.id}`, { method: 'PUT', token, body: configuration })
    : await request(path, { method: 'POST', token, body: configuration, expected: [201] });
  const connection = await request(`${path}/${provider.id}/test`, { method: 'POST', token });
  if (!connection.success) throw new Error('SMTP connection test failed');
  if (!provider.isShared) {
    provider = await request(`${path}/${provider.id}/share`, { method: 'PATCH', token });
  }
  if (!provider.isDefault) {
    provider = await request(`${path}/${provider.id}/default`, { method: 'PATCH', token });
  }
  if (!provider.isSystemProvider) {
    await request(`${path}/${provider.id}/system`, { method: 'PATCH', token });
  }
}

await waitForHealth();
await ensureBootstrap();
const accessToken = await authenticate();
await request('/app-settings/allow_registration', {
  method: 'PATCH',
  token: accessToken,
  body: { value: 'false' },
});
await reconcileProvider(accessToken);
const libraries = await ensureLibraries(accessToken);
for (const library of libraries) await reconcileLibraryAccess(accessToken, library);
await reconcileProwlarr(accessToken);
await reconcileEmail(accessToken);
await reconcileMetadataAndHardcover(accessToken);
console.log('BookOrbit OIDC, registration policy, authoritative libraries, library access, Prowlarr, SMTP, metadata providers, and Hardcover reconciled');
