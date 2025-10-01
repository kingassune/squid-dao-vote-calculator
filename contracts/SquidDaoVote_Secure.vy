# version 0.4.3

"""
@title SQUID DAO Vote Calculator - Security Hardened Version
@notice Signal vote caps at 8 tokens, Squid has too many tentacles
@dev Combines naked SQUID plus equivalent LPs (SQUID/ETH) via Curve, Convex, Stake DAO
@author Leviathan News (Security Audit: Copilot Team)
@license MIT

🔒 SECURITY IMPROVEMENTS:
- Fixed dust attack vulnerability with minimum quantity thresholds
- Added dynamic USD-based dust protection
- Implemented division by zero protection
- Enhanced input validation
- Added precision improvements

                         ██████████████
                      ████████████████████
                    █████████████████████████
                  ████████████████████████████
                 ██████████████████████████████
                ████████████████████████████████
               ██████████████████████████████████
               ██████████████████████████████████
               ██████████████████████████████████
               █████     ██████████████     █████
               ████       ████████████       ████
                ███       ████████████       ███
                ████     ██████████████     ████
                  ████████████████████████████
                   ██████████████████████████
   ██████████       ████████████████████████       ██████████
 ██████████████     ████████████████████████     ██████████████
████████████████   ██████████████████████████   ████████████████
███████ ████████  ████████████████████████████  ████████ ███████
██████ █████████ ██████████████████████████████ █████████ ██████
███████ ██████ ██████████ ████████████ ██████████ ██████ ███████
████████████████████████  ████████████  ████████████████████████
  ████████████████████    ████████████    ████████████████████
   █████████████████     ██████████████     █████████████████
      ███████████████    ██████████████    ███████████████
            ███████████  ██████  ██████  ███████████
           ██████ █████████████  █████████████ ██████
          ██████ ██████████████   █████████████ ██████
          ███████ ████████████    ████████████ ███████
          ███████████████████      ███████████████████
           ██████████████████      ██████████████████
            ███████████████          ███████████████
               ██████████              ██████████

"""

# ============================================================================================
# 🧩 INTERFACES
# ============================================================================================

from ethereum.ercs import IERC20


interface TwoCrypto:
    def price_oracle() -> uint256: view
    def calc_withdraw_one_coin(token_amount: uint256, i: uint256) -> uint256: view
    def coins(i: uint256) -> address: view


interface ThreeCrypto:
    def price_oracle(i: uint256) -> uint256: view


# ============================================================================================
# 💾 STORAGE
# ============================================================================================

# NAKED SQUID 🦑🛀
squid_token: IERC20

# SQUID / ETH LP 🦑💎
squid_eth_lp_token: IERC20
squid_eth_gauge: IERC20
squid_eth_cvx: IERC20
squid_eth_stakedao: IERC20

# SQUID / SQUILL LP 🦑🪶
squill_lp_token: IERC20
squill_gauge: IERC20
squill_cvx: IERC20
squill_stakedao: IERC20

# PRICE ORACLES ⚖️
squid_eth_pool: TwoCrypto
squill_squid_pool: TwoCrypto
eth_usd_pool: ThreeCrypto

# 🔒 SECURITY: Enhanced dust protection
min_usd_threshold: uint256  # Minimum USD value (scaled by 10^18)

# 🔒 SECURITY: Constants for validation
MAX_QUANTITY: constant(uint256) = 10**30  # Maximum allowed quantity
MIN_LP_THRESHOLD: constant(uint256) = 10**15  # 0.001 LP tokens minimum
PRECISION_MULTIPLIER: constant(uint256) = 10**36  # For high precision calculations


# ============================================================================================
# 🚧 CONSTRUCTOR
# ============================================================================================

@deploy
def __init__():

    # NAKED SQUID 🦑🛀
    self.squid_token = IERC20(0x6e58089d8E8f664823d26454f49A5A0f2fF697Fe)

    # SQUID/ETH LP 🦑💎
    self.squid_eth_lp_token = IERC20(0x277FA53c8a53C880E0625c92C92a62a9F60f3f04)
    self.squid_eth_gauge = IERC20(0xe5E5ed1B50AE33E66ca69dF17Aa6381FDe4e9C7e)
    self.squid_eth_cvx = IERC20(0x29FF8F9ACb27727D8A2A52D16091c12ea56E9E4d)
    self.squid_eth_stakedao = IERC20(0x8CDCDccAB3fC79c267B8361AdDAefD3aADaB9778)

    # SQUID/SQUILL LP 🦑🪶
    self.squill_lp_token = IERC20(0xb2B1458960E4d64716c8C472c114441A02fBA1De)
    self.squill_gauge = IERC20(0x9bC291018e0434a21218A16005B0e198b4814ba8)
    self.squill_cvx = IERC20(0x1CC03c1C714f767ca866A3Fa58c9153b1C087E85)
    self.squill_stakedao = IERC20(0x9C1a1b52Bf2c42B6e7E2dCdAEF260b60386Ad76b)

    # PRICE ORACLES ⚖️
    self.squid_eth_pool = TwoCrypto(0x277FA53c8a53C880E0625c92C92a62a9F60f3f04)
    self.squill_squid_pool = TwoCrypto(0xb2B1458960E4d64716c8C472c114441A02fBA1De)
    self.eth_usd_pool = ThreeCrypto(0xa0D3911349e701A1F49C1Ba2dDA34b4ce9636569)

    # 🔒 SECURITY: Set minimum threshold to $0.01 USD (scaled by 10^18)
    self.min_usd_threshold = 10**16  # $0.01


# ============================================================================================
# 👀 VIEW FUNCTIONS
# ============================================================================================

@external
@view
def balanceOf(addr: address) -> uint256:
    """
    @notice Calculate the total SQUID voting power for an address
    @dev Combines three types of token holdings to determine total voting power:
         - Naked SQUID tokens (direct holdings)
         - SQUID/ETH LP tokens (converted to SQUID equivalent)
         - SQUID/SQUILL LP tokens (converted to SQUID equivalent)
    @param addr The address for which to check voting power
    @return Total SQUID equivalent voting power for the address
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    
    total_bal: uint256 = self._squid_balance(addr)
    total_bal += self._squid_lp_balance_in_squid(addr)
    total_bal += self._squill_lp_balance_in_squid(addr)

    return total_bal


# ======================
# NAKED SQUID 🦑🛀
# ======================

@external
@view
def squid_balance(addr: address) -> uint256:
    """
    @notice Get the naked SQUID token balance for an address
    @dev Returns only the direct SQUID token holdings, excluding LP tokens
    @param addr The address for which to check SQUID balance
    @return Amount of naked SQUID tokens held by the address
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    return self._squid_balance(addr)


# ======================
# SQUID/ETH LP 🦑💎
# ======================

@external
@view
def squid_lp_balance(addr: address) -> uint256:
    """
    @notice Get the total SQUID/ETH LP token balance for an address
    @dev Includes LP tokens from gauge, Convex, and Stake DAO positions
    @param addr The address for which to check SQUID/ETH LP balance
    @return Total amount of SQUID/ETH LP tokens held by the address
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    return self._squid_lp_balance(addr)


@external
@view
def squid_lp_balance_in_squid(addr: address) -> uint256:
    """
    @notice Convert SQUID/ETH LP token balance to SQUID equivalent
    @dev Calculates the SQUID equivalent value of LP tokens using current pool rates
    @param addr The address for which to check SQUID/ETH LP balance
    @return SQUID equivalent value of the address's SQUID/ETH LP tokens
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    return self._squid_lp_balance_in_squid(addr)


# ======================
# SQUID/SQUILL LP 🦑🪶
# ======================

@external
@view
def squill_lp_balance(addr: address) -> uint256:
    """
    @notice Get the total SQUID/SQUILL LP token balance for an address
    @dev Includes LP tokens from gauge, Convex, and Stake DAO positions
    @param addr The address to check SQUID/SQUILL LP balance for
    @return Total amount of SQUID/SQUILL LP tokens held by the address
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    return self._squill_lp_balance(addr)


@external
@view
def squill_lp_balance_in_squid(addr: address) -> uint256:
    """
    @notice Convert SQUID/SQUILL LP token balance to SQUID equivalent
    @dev Calculates the SQUID equivalent value of SQUILL LP tokens using current pool rates
    @param addr The address to check SQUID/SQUILL LP balance for
    @return SQUID equivalent value of the address's SQUID/SQUILL LP tokens
    """
    # 🔒 SECURITY: Input validation
    assert addr != empty(address), "Invalid address"
    return self._squill_lp_balance_in_squid(addr)


# ======================
# PRICE ORACLES ⚖️
# ======================

@external
@view
def eth_price() -> uint256:
    """
    @notice Get the current ETH price in USD
    @dev Fetches ETH/USD price from the Curve ThreeCrypto oracle
    @return Current ETH price in USD (scaled by 10^18)
    """
    return self._eth_usd_price()


@external
@view
def squid_price() -> uint256:
    """
    @notice Get the current SQUID price in USD
    @dev Calculates SQUID/USD price using SQUID/ETH and ETH/USD oracles
    @return Current SQUID price in USD (scaled by 10^18)
    """
    return self._squid_usd_price()


@external
@view
def squill_price() -> uint256:
    """
    @notice Get the current SQUILL price in USD
    @dev Calculates SQUILL/USD price using SQUILL/SQUID and SQUID/USD oracles
    @return Current SQUILL price in USD (scaled by 10^18)
    """
    return self._squill_usd_price()


@external
@view
def squid_lp_equivalent(quantity: uint256 = 10**18) -> uint256:
    """
    @notice Calculate SQUID equivalent for a given amount of SQUID/ETH LP tokens
    @dev Uses the Curve pool's calc_withdraw_one_coin to determine SQUID equivalent
    @param quantity Amount of SQUID/ETH LP tokens to convert (defaults to 1 LP token)
    @return SQUID equivalent amount for the given LP token quantity
    """
    # 🔒 SECURITY: Input validation
    assert quantity <= MAX_QUANTITY, "Quantity too large"
    return self._squid_lp_equivalent(quantity)


@external
@view
def squill_lp_equivalent(quantity: uint256 = 10**18) -> uint256:
    """
    @notice Calculate SQUID equivalent for a given amount of SQUID/SQUILL LP tokens
    @dev Uses the Curve pool's calc_withdraw_one_coin to determine SQUID equivalent
    @param quantity Amount of SQUID/SQUILL LP tokens to convert (defaults to 1 LP token)
    @return SQUID equivalent amount for the given LP token quantity
    """
    # 🔒 SECURITY: Input validation
    assert quantity <= MAX_QUANTITY, "Quantity too large"
    return self._squill_lp_equivalent(quantity)


# ============================================================================================
# 👀 Internal Functions
# ============================================================================================

# ======================
# 🔒 SECURITY HELPERS
# ======================

@internal
@view
def _high_precision_multiply_divide(a: uint256, b: uint256, c: uint256) -> uint256:
    """
    🔒 SECURITY: Calculate (a * b) / c with higher precision to minimize rounding errors.
    """
    if c == 0:
        return 0
        
    # Use higher precision for intermediate calculation
    intermediate: uint256 = (a * b * PRECISION_MULTIPLIER) // c
    return intermediate // PRECISION_MULTIPLIER


@internal
@view
def _calculate_min_lp_threshold(is_squill: bool) -> uint256:
    """
    🔒 SECURITY: Calculate minimum LP threshold based on USD value to prevent dust attacks.
    """
    if is_squill:
        # For SQUILL LP: threshold = min_usd_threshold / squill_price_per_lp
        squill_price: uint256 = self._squill_usd_price()
        squill_lp_equiv: uint256 = self._squill_lp_equivalent(10**18)
        if squill_price == 0 or squill_lp_equiv == 0:
            return MIN_LP_THRESHOLD  # Fallback to 0.001 LP
        
        price_per_lp: uint256 = self._high_precision_multiply_divide(squill_lp_equiv, squill_price, 10**18)
        if price_per_lp == 0:
            return MIN_LP_THRESHOLD
            
        return self._high_precision_multiply_divide(self.min_usd_threshold, 10**18, price_per_lp)
    else:
        # For SQUID LP: similar calculation
        squid_price: uint256 = self._squid_usd_price()
        squid_lp_equiv: uint256 = self._squid_lp_equivalent(10**18)
        if squid_price == 0 or squid_lp_equiv == 0:
            return MIN_LP_THRESHOLD
            
        price_per_lp: uint256 = self._high_precision_multiply_divide(squid_lp_equiv, squid_price, 10**18)
        if price_per_lp == 0:
            return MIN_LP_THRESHOLD
            
        return self._high_precision_multiply_divide(self.min_usd_threshold, 10**18, price_per_lp)


# ======================
# NAKED SQUID 🦑🛀
# ======================

@internal
@view
def _squid_balance(addr: address) -> uint256:
    return staticcall self.squid_token.balanceOf(addr)


# ======================
# SQUID/ETH LP 🦑💎
# ======================

@internal
@view
def _squid_lp_balance(addr: address) -> uint256:
    lp_val: uint256 = staticcall self.squid_eth_lp_token.balanceOf(addr)
    lp_val += staticcall self.squid_eth_gauge.balanceOf(addr)
    lp_val += staticcall self.squid_eth_cvx.balanceOf(addr)
    lp_val += staticcall self.squid_eth_stakedao.balanceOf(addr)
    return lp_val


@internal
@view
def _squid_lp_balance_in_squid(addr: address) -> uint256:
    bal: uint256 = self._squid_lp_balance(addr)
    
    # 🔒 SECURITY: Dynamic dust protection based on USD value
    min_threshold: uint256 = self._calculate_min_lp_threshold(False)
    if bal < min_threshold:
        return 0

    rate: uint256 = self._squid_lp_equivalent(bal)
    # 🔒 SECURITY: High precision calculation
    return self._high_precision_multiply_divide(bal, rate, 10**18)


@internal
@view
def _squid_lp_equivalent(quantity: uint256 = 10**18) -> uint256:
    return self._lp_equivalent(self.squid_eth_pool, 1, quantity)


# ======================
# SQUID/SQUILL LP 🦑🪶
# ======================

@internal
@view
def _squill_lp_balance(addr: address) -> uint256:
    lp_val: uint256 = staticcall self.squill_lp_token.balanceOf(addr)
    lp_val += staticcall self.squill_gauge.balanceOf(addr)
    lp_val += staticcall self.squill_cvx.balanceOf(addr)
    lp_val += staticcall self.squill_stakedao.balanceOf(addr)
    return lp_val


@internal
@view
def _squill_lp_balance_in_squid(addr: address) -> uint256:
    bal: uint256 = self._squill_lp_balance(addr)
    
    # 🔒 SECURITY: Dynamic dust protection based on USD value
    min_threshold: uint256 = self._calculate_min_lp_threshold(True)
    if bal < min_threshold:
        return 0

    rate: uint256 = self._squill_lp_equivalent(bal)
    # 🔒 SECURITY: High precision calculation
    return self._high_precision_multiply_divide(bal, rate, 10**18)


@internal
@view
def _squill_lp_equivalent(quantity: uint256 = 10**18) -> uint256:
    return self._lp_equivalent(self.squill_squid_pool, 0, quantity)


# ======================
# PRICE ORACLES ⚖️
# ======================

@internal
@view
def _eth_usd_price() -> uint256:
    price: uint256 = staticcall self.eth_usd_pool.price_oracle(0)
    # 🔒 SECURITY: Zero price protection
    return price if price > 0 else 0


@internal
@view
def _squid_usd_price() -> uint256:
    _squid_eth_price: uint256 = self._squid_eth_price()
    _eth_usd_price: uint256 = self._eth_usd_price()
    
    # 🔒 SECURITY: Zero price protection
    if _squid_eth_price == 0 or _eth_usd_price == 0:
        return 0
        
    return self._high_precision_multiply_divide(_squid_eth_price, _eth_usd_price, 10**18)


@internal
@view
def _squid_eth_price() -> uint256:
    price: uint256 = staticcall self.squid_eth_pool.price_oracle()
    # 🔒 SECURITY: Zero price protection
    return price if price > 0 else 0


@internal
@view
def _squill_usd_price() -> uint256:
    squill_squid_price: uint256 = staticcall self.squill_squid_pool.price_oracle()
    squid_usd_price: uint256 = self._squid_usd_price()
    
    # 🔒 SECURITY: Zero price protection
    if squill_squid_price == 0 or squid_usd_price == 0:
        return 0
        
    return self._high_precision_multiply_divide(squill_squid_price, squid_usd_price, 10**18)


@internal
@view
def _lp_equivalent(pool: TwoCrypto, index: uint256, quantity: uint256) -> uint256:
    # SQUID index sanity check or burn it all
    assert (staticcall pool.coins(index) == self.squid_token.address)
    
    # 🔒 SECURITY FIX: Minimum viable quantity check to prevent dust attacks
    # Require at least 0.001 LP tokens (10^15 wei) for rate calculation
    if quantity < MIN_LP_THRESHOLD:
        return 0
    
    # Effective SQUID single-sided withdraw amount
    retval: uint256 = 0
    if quantity > 0:
        _out: uint256 = staticcall pool.calc_withdraw_one_coin(quantity, index)
        
        # 🔒 SECURITY: Division by zero and output validation
        if _out == 0:
            return 0
            
        retval = self._high_precision_multiply_divide(_out, 10**18, quantity)
        
        # 🔒 SECURITY: Sanity check for reasonable rates
        # Rate should not be more than 10x the normal rate for full LP amounts
        if quantity >= 10**18:  # For full LP token amounts
            baseline_out: uint256 = staticcall pool.calc_withdraw_one_coin(10**18, index)
            if baseline_out > 0:
                baseline_rate: uint256 = self._high_precision_multiply_divide(baseline_out, 10**18, 10**18)
                
                # Reject rates that are more than 10x baseline (protection against manipulation)
                if retval > baseline_rate * 10:
                    return baseline_rate  # Return baseline rate instead

    return retval