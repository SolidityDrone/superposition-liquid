import sys, json, urllib.request
from eth_account import Account
from Crypto.Hash import keccak

rpc, weth, key, value = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4])
acct = Account.from_key(key.to_bytes(32, "big"))
def rpc_call(method, params):
    body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(rpc, data=body, headers={"Content-Type": "application/json"})
    resp = json.loads(urllib.request.urlopen(req).read())
    if "result" not in resp:
        raise RuntimeError(f"{method} failed: {resp}")
    return resp["result"]

nonce = int(rpc_call("eth_getTransactionCount", [acct.address, "latest"]), 16)
chain_id = int(rpc_call("eth_chainId", []), 16)
gas_price = int(rpc_call("eth_gasPrice", []), 16)
k = keccak.new(digest_bits=256); k.update(b"deposit()")
data = k.digest()[:4]
tx = {"to": weth, "value": value, "gas": 60000, "gasPrice": gas_price, "nonce": nonce, "chainId": chain_id, "data": data}
signed = acct.sign_transaction(tx)
h = rpc_call("eth_sendRawTransaction", ["0x" + signed.raw_transaction.hex()])
print("wrapped:", h if isinstance(h, str) else json.dumps(h))
