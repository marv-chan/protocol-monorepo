{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE TypeFamilies           #-}

module Money.Systems.Superfluid.Token
    ( module Money.Systems.Superfluid.MoneyUnit
    , Address
    , Account (..)
    , Token (..)
    ) where

import           Data.Default
import           Data.Kind                                                        (Type)
import           Data.Maybe                                                       (fromMaybe)

import           Money.Systems.Superfluid.Concepts
--
import qualified Money.Systems.Superfluid.Agreements.ConstantFlowAgreement        as CFA
import qualified Money.Systems.Superfluid.Agreements.DecayingFlowAgreement        as DFA
import qualified Money.Systems.Superfluid.Agreements.TransferableBalanceAgreement as TBA
--
import qualified Money.Systems.Superfluid.SubSystems.BufferBasedSolvency          as BBS
--
import           Money.Systems.Superfluid.MoneyUnit

-- | Address type class.
--
-- Notional conventions:
--  * Type name: addr
--  * SuperfluidTypes indexed type synonym: SFT_ADDR
class (Eq addr) => Address addr

-- | MoneyUnit type class.
--
-- Notional conventions:
--   * Type name: acc
--   * Type family name: SF_ACC
--   * Term name: *MoneyUnit
class (SuperfluidTypes sft, MoneyUnit acc sft) => Account acc sft | acc -> sft where
    type ACC_ADDR acc :: Type
    addressOfAccount :: acc -> ACC_ADDR acc

-- | Token Type Class
--
-- Notional conventions:
--   * Type name: tk
--   * Term name: *Token
--
-- Notes:
--
-- * Token is a monadic type, where all its functions run within the monadic context.
-- * Token provides:
--   * addressable account,
--   * and agreement (TBA/CFA/GDA) operations.
-- * Instructions for write operations are executed in `execTokenInstructions`.
class ( Monad tk
      , SuperfluidTypes (TK_SFT tk)
      , Account (TK_ACC tk) (TK_SFT tk)
      ) => Token tk where

    type TK_SFT tk :: Type
    type TK_ACC tk :: Type

    --
    -- System functions
    --

    getCurrentTime :: tk (TS tk)

    --
    -- Account data
    --

    getAccount :: ADDR tk -> tk (TK_ACC tk)

    putAccount :: ADDR tk -> TK_ACC tk -> tk ()

    balanceOfAccount :: ADDR tk -> tk (RTB tk)
    balanceOfAccount addr = do
        t <- getCurrentTime
        account <- getAccount addr
        return $ balanceOfAt account t

    --
    -- TBA functions
    --

    getMinterAddress :: tk (ADDR tk)

    mintLiquidity :: ADDR tk -> LQ tk-> tk ()
    mintLiquidity toAddr amount = do
        t <- getCurrentTime
        minterAddress <- getMinterAddress
        mintFrom <- getAccount minterAddress
        mintTo <- getAccount toAddr
        let (_, TBA.TBAPartiesF mintFromACD' mintToACD') = updateAgreement
                TBA.TBAContractData
                (TBA.TBAPartiesF (viewTBA mintFrom) (viewTBA mintTo))
                (TBA.MintLiquidity amount)
        putAccount minterAddress $ setTBA mintFrom mintFromACD' t
        putAccount toAddr $ setTBA mintTo mintToACD' t

    --
    -- CFA functions
    --

    calcFlowBuffer :: LQ tk-> tk (LQ tk)

    viewFlow :: CFA.CFAPartiesF (TK_SFT tk) (ADDR tk) -> tk (Maybe (CFA.CFAContractData (TK_SFT tk)))
    setFlow :: CFA.CFAPartiesF (TK_SFT tk) (ADDR tk) -> CFA.CFAContractData (TK_SFT tk) -> TS tk -> tk ()

    updateFlow :: ADDR tk -> ADDR tk -> LQ tk-> tk ()
    updateFlow senderAddr receiverAddr newFlowRate = do
        t <- getCurrentTime
        senderAccount <- getAccount senderAddr
        receiverAccount <- getAccount receiverAddr
        flowACD <- fromMaybe def <$> viewFlow (CFA.CFAPartiesF senderAddr receiverAddr)
        newFlowBuffer <- BBS.mkBufferLiquidity <$> calcFlowBuffer newFlowRate
        let (flowACD', CFA.CFAPartiesF senderFlowAAD' receiverFlowAAD') = updateAgreement
                flowACD
                (CFA.CFAPartiesF (viewCFA senderAccount) (viewCFA receiverAccount))
                (CFA.UpdateFlow newFlowRate newFlowBuffer t)
        setFlow (CFA.CFAPartiesF senderAddr receiverAddr) flowACD' t
        putAccount senderAddr $ setCFA senderAccount senderFlowAAD' t
        putAccount receiverAddr $ setCFA receiverAccount receiverFlowAAD' t

    --
    -- DFA functions
    --

    viewDecayingFlow :: DFA.DFAPartiesF (TK_SFT tk) (ADDR tk) -> tk (Maybe (DFA.DFAContractData (TK_SFT tk)))
    setDecayingFlow :: DFA.DFAPartiesF (TK_SFT tk) (ADDR tk) -> DFA.DFAContractData (TK_SFT tk) -> TS tk -> tk ()

    updateDecayingFlow :: ADDR tk -> ADDR tk -> LQ tk-> tk ()
    updateDecayingFlow senderAddr receiverAddr newDistributionLimit = do
        t <- getCurrentTime
        senderAccount <- getAccount senderAddr
        receiverAccount <- getAccount receiverAddr
        flowACD <- fromMaybe def <$> viewDecayingFlow (DFA.DFAPartiesF senderAddr receiverAddr)
        let (flowACD', DFA.DFAPartiesF senderFlowAAD' receiverFlowAAD') = updateAgreement
                flowACD
                (DFA.DFAPartiesF (viewDFA senderAccount) (viewDFA receiverAccount))
                (DFA.UpdateDecayingFlow newDistributionLimit def t)
        setDecayingFlow (DFA.DFAPartiesF senderAddr receiverAddr) flowACD' t
        putAccount senderAddr $ setDFA senderAccount senderFlowAAD' t
        putAccount receiverAddr $ setDFA receiverAccount receiverFlowAAD' t

-- ============================================================================
-- Internal
--
type TS tk = SFT_TS (TK_SFT tk)
type LQ tk = SFT_LQ (TK_SFT tk)
type RTB tk = SFT_RTB (TK_SFT tk)
type ADDR tk = ACC_ADDR (TK_ACC tk)