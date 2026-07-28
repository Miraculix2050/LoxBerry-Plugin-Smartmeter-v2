<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');

function respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES) . "\n";
    exit;
}

function read_json_object(string $file): ?array
{
    if (!is_file($file) || !is_readable($file)) {
        return null;
    }
    $content = file_get_contents($file);
    if ($content === false) {
        return null;
    }
    $data = json_decode($content, true);
    return is_array($data) ? $data : null;
}

function normalized_remote_address(): string
{
    $address = (string)($_SERVER['REMOTE_ADDR'] ?? '');
    if (preg_match('/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i', $address, $match)) {
        return $match[1];
    }
    return $address;
}

function update_authentication_rate_limit(string $file, string $address, string $operation): bool
{
    $directory = dirname($file);
    if (!is_dir($directory) && !mkdir($directory, 0750, true) && !is_dir($directory)) {
        return true;
    }
    $handle = fopen($file, 'c+');
    if ($handle === false || !flock($handle, LOCK_EX)) {
        if (is_resource($handle)) {
            fclose($handle);
        }
        return true;
    }

    $content = stream_get_contents($handle);
    $state = is_string($content) && $content !== '' ? json_decode($content, true) : [];
    if (!is_array($state)) {
        $state = [];
    }
    $now = time();
    foreach ($state as $source => $attempts) {
        if (!is_array($attempts)) {
            unset($state[$source]);
            continue;
        }
        $state[$source] = array_values(array_filter(
            $attempts,
            static fn($timestamp): bool => is_int($timestamp) && $timestamp > $now - 60
        ));
        if ($state[$source] === []) {
            unset($state[$source]);
        }
    }

    $limited = count($state[$address] ?? []) >= 5;
    if ($operation === 'failure' && !$limited) {
        $state[$address][] = $now;
    } elseif ($operation === 'success') {
        unset($state[$address]);
    }

    rewind($handle);
    ftruncate($handle, 0);
    fwrite($handle, json_encode($state, JSON_UNESCAPED_SLASHES));
    fflush($handle);
    chmod($file, 0640);
    flock($handle, LOCK_UN);
    fclose($handle);
    return $limited;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, ['ok' => false, 'error' => 'method_not_allowed']);
}

$target = (string)($_GET['target'] ?? '');
if (!in_array($target, ['vzlogger', 'bridge', 'all'], true)) {
    respond(400, ['ok' => false, 'error' => 'invalid_target']);
}

$pluginFolder = basename(__DIR__);
$installFolder = dirname(__DIR__, 4);
$configFile = "$installFolder/config/plugins/$pluginFolder/smartmeter_recovery.json";
$controller = "$installFolder/bin/plugins/$pluginFolder/vzlogger_control.pl";
$runtimeDir = "/var/run/shm/$pluginFolder";
$remoteAddress = normalized_remote_address();
$rateFile = "$runtimeDir/recovery-auth.json";

if (update_authentication_rate_limit($rateFile, $remoteAddress, 'check')) {
    respond(429, ['ok' => false, 'error' => 'too_many_requests']);
}

$settings = read_json_object($configFile);
$providedToken = (string)($_SERVER['HTTP_X_SMARTMETER_RECOVERY_TOKEN'] ?? '');
$providedHash = hash('sha256', $providedToken);
$storedHash = is_array($settings) ? (string)($settings['token_sha256'] ?? '') : '';
$authorized = is_array($settings)
    && ($settings['enabled'] ?? false) === true
    && $providedToken !== ''
    && preg_match('/^[a-f0-9]{64}$/', $storedHash) === 1
    && hash_equals($storedHash, $providedHash);

if ($authorized && ($settings['ip_check_enabled'] ?? false) === true) {
    $allowed = $settings['allowed_ips'] ?? [];
    $authorized = is_array($allowed) && in_array($remoteAddress, $allowed, true);
}

if (!$authorized) {
    update_authentication_rate_limit($rateFile, $remoteAddress, 'failure');
    error_log("SmartMeter recovery authorization failed for source " . $remoteAddress);
    respond(403, ['ok' => false, 'error' => 'forbidden']);
}

update_authentication_rate_limit($rateFile, $remoteAddress, 'success');
if (!is_file($controller)) {
    respond(503, ['ok' => false, 'error' => 'controller_unavailable']);
}

$command = escapeshellarg('/usr/bin/perl') . ' ' . escapeshellarg($controller) . ' ' . escapeshellarg("recover-$target");
$lines = [];
$exitCode = 1;
exec($command, $lines, $exitCode);
$payload = json_decode(implode("\n", $lines), true);
if (!is_array($payload)) {
    respond(503, ['ok' => false, 'error' => 'invalid_controller_response']);
}

$status = $exitCode === 0 ? 200 : 503;
$reasons = [];
foreach (($payload['services'] ?? []) as $service) {
    if (is_array($service) && isset($service['reason'])) {
        $reasons[] = $service['reason'];
    }
}
if ($reasons !== [] && count(array_unique($reasons)) === 1 && $reasons[0] === 'cooldown') {
    $status = 429;
} elseif (in_array('busy', $reasons, true)) {
    $status = 409;
}
respond($status, $payload);
