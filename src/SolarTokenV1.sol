// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SolarTokenV1
 * @author NIKO-SUN
 */
contract SolarTokenV1 is ERC1155, AccessControl, Pausable, ReentrancyGuard {
    // ============ ROLES ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ STRUCTS (STORAGE PACKED) ============

    /**
     * @notice Proyecto solar tokenizado
     */
    struct Project {
        uint96 totalSupply; // Total de tokens del proyecto
        uint96 minted; // Tokens ya minteados
        uint64 priceWei; // Precio por token en wei
        bool active; // Estado activo/inactivo
        uint64 createdAt; // Timestamp de creación
    }

    /**
     * @notice Métricas agregadas del proyecto
     */
    struct Metrics {
        uint128 totalEnergyKwh; // Energía acumulada (kWh * 10^4 para decimales)
        uint128 totalDistributed; // Total distribuido en wei
        uint64 lastUpdate; // Timestamp última actualización
    }

    // ============ STORAGE ============

    /// @notice Mapping de projectId a Project
    /// @dev projectId es autoincrementable (1, 2, 3...)
    mapping(uint256 => Project) public projects;

    /// @notice Mapping de projectId a Metrics
    mapping(uint256 => Metrics) public metrics;

    /// @notice Contador de proyectos (autoincrementable)
    uint256 private _nextProjectId = 1;

    /// @notice Base URI para metadata (configurable)
    /// @dev Puede apuntar a IPFS, backend, o cualquier fuente
    /// @dev Ejemplos:
    ///      - "https://api.nikosun.com/metadata/" (backend dinámico)
    ///      - "ipfs://QmYourIPFSHash/" (descentralizado)
    ///      - "https://gateway.ipfs.io/ipfs/QmHash/" (gateway IPFS)
    string public baseURI;

    // ============ EVENTS ============

    /**
     * @notice Emitido cuando se crea un proyecto
     * @param projectId ID autogenerado del proyecto (1, 2, 3...)
     * @param totalSupply Total de tokens disponibles
     * @param priceWei Precio por token en wei
     * @param createdAt Timestamp de creación
     */
    event ProjectCreated(
        uint256 indexed projectId,
        uint96 totalSupply,
        uint64 priceWei,
        uint64 createdAt
    );

    /**
     * @notice Emitido cuando se mintean tokens
     * @param projectId ID del proyecto
     * @param to Dirección que recibe los tokens
     * @param amount Cantidad de tokens minteados
     * @param totalPaid Total pagado en wei
     */
    event TokensMinted(
        uint256 indexed projectId,
        address indexed to,
        uint96 amount,
        uint256 totalPaid
    );

    /**
     * @notice Emitido cuando se actualizan métricas de energía
     * @param projectId ID del proyecto
     * @param energyDelta Incremento de energía (kWh * 10^4)
     * @param timestamp Timestamp de actualización
     */
    event MetricsUpdated(
        uint256 indexed projectId,
        uint128 energyDelta,
        uint64 timestamp
    );

    /**
     * @notice Emitido cuando se registra un pago
     * @param projectId ID del proyecto
     * @param amount Monto distribuido en wei
     * @param timestamp Timestamp de distribución
     */
    event PayoutRecorded(
        uint256 indexed projectId,
        uint128 amount,
        uint64 timestamp
    );

    /**
     * @notice Emitido cuando cambia el estado de un proyecto
     * @param projectId ID del proyecto
     * @param active Nuevo estado
     */
    event ProjectStatusChanged(uint256 indexed projectId, bool active);

    /**
     * @notice Emitido cuando se actualiza el base URI
     * @param newBaseURI Nueva URI base
     */
    event BaseURIUpdated(string newBaseURI);

    // ============ CUSTOM ERRORS (GAS OPTIMIZATION) ============

    /// @notice Proyecto no está activo
    error ProjectNotActive();

    /// @notice La cantidad excede el total supply
    error ExceedsTotalSupply();

    /// @notice Pago insuficiente
    error InsufficientPayment();

    /// @notice Proyecto no existe
    error InvalidProject();

    /// @notice Cantidad inválida (0 o negativa)
    error InvalidAmount();

    /// @notice No autorizado
    error Unauthorized();

    /// @notice Transferencia falló
    error TransferFailed();

    // ============ CONSTRUCTOR ============

    /**
     * @notice Inicializa el contrato
     * @param _baseURI URI base para metadata (puede ser IPFS, backend, etc.)
     * @dev Backend es opcional, puede ser cualquier fuente de metadata
     */
    constructor(string memory _baseURI) ERC1155("") {
        baseURI = _baseURI;

        // Otorgar todos los roles al deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Crear nuevo proyecto solar
     * @param totalSupply Total de tokens del proyecto
     * @param priceWei Precio por token en wei
     * @return projectId ID autogenerado del proyecto
     */
    function createProject(
        uint96 totalSupply,
        uint64 priceWei
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        if (totalSupply == 0) revert InvalidAmount();

        uint256 projectId = _nextProjectId++;

        projects[projectId] = Project({
            totalSupply: totalSupply,
            minted: 0,
            priceWei: priceWei,
            active: true,
            createdAt: uint64(block.timestamp)
        });

        emit ProjectCreated(
            projectId,
            totalSupply,
            priceWei,
            uint64(block.timestamp)
        );
        return projectId;
    }

    /**
     * @notice Actualizar métricas de energía del proyecto
     * @param projectId ID del proyecto
     * @param energyDelta Incremento de energía en kWh * 10^4
     *
     * @dev Solo admin puede actualizar, basado en cálculos del backend
     * @dev Se multiplica por 10^4 para mantener 4 decimales
     */
    function updateMetrics(
        uint256 projectId,
        uint128 energyDelta
    ) external onlyRole(ADMIN_ROLE) {
        if (!projects[projectId].active) revert ProjectNotActive();

        Metrics storage m = metrics[projectId];
        m.totalEnergyKwh += energyDelta;
        m.lastUpdate = uint64(block.timestamp);

        emit MetricsUpdated(projectId, energyDelta, uint64(block.timestamp));
    }

    /**
     * @notice Registrar distribución de pagos a inversores
     * @param projectId ID del proyecto
     * @param amount Monto total distribuido en wei
     *
     * @dev Solo admin puede registrar distribuciones
     * @dev Este es solo un registro on-chain, no transfiere fondos
     */
    function recordPayout(
        uint256 projectId,
        uint128 amount
    ) external onlyRole(ADMIN_ROLE) {
        if (!projects[projectId].active) revert ProjectNotActive();

        metrics[projectId].totalDistributed += amount;

        emit PayoutRecorded(projectId, amount, uint64(block.timestamp));
    }

    /**
     * @notice Cambiar estado activo/inactivo del proyecto
     * @param projectId ID del proyecto
     * @param active Nuevo estado
     *
     * @dev Pausar proyecto impide mint pero no afecta transfers
     */
    function setProjectStatus(
        uint256 projectId,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        if (projects[projectId].totalSupply == 0) revert InvalidProject();
        projects[projectId].active = active;
        emit ProjectStatusChanged(projectId, active);
    }

    /**
     * @notice Actualizar precio de un proyecto
     * @param projectId ID del proyecto
     * @param newPriceWei Nuevo precio en wei
     *
     * @dev Solo si no se han minteado tokens aún
     * @dev Previene cambiar precio después de que usuarios compraron
     */
    function updatePrice(
        uint256 projectId,
        uint64 newPriceWei
    ) external onlyRole(ADMIN_ROLE) {
        if (projects[projectId].minted > 0) revert Unauthorized();
        projects[projectId].priceWei = newPriceWei;
    }

    /**
     * @notice Actualizar base URI para metadata
     * @param newBaseURI Nueva URI base
     *
     * @dev Permite cambiar la fuente de metadata sin redeploy
     * @dev Útil para migrar de backend a IPFS, o viceversa
     *
     */
    function setBaseURI(
        string calldata newBaseURI
    ) external onlyRole(ADMIN_ROLE) {
        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Comprar tokens de un proyecto
     * @param projectId ID del proyecto
     * @param amount Cantidad de tokens a comprar
     *
     * @dev Usuario debe enviar SYS suficiente
     * @dev Exceso de pago es devuelto automáticamente
     */
    function mint(
        uint256 projectId,
        uint96 amount
    ) external payable whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        Project storage project = projects[projectId];

        // Validaciones
        if (!project.active) revert ProjectNotActive();
        if (project.minted + amount > project.totalSupply)
            revert ExceedsTotalSupply();

        uint256 totalPrice = uint256(project.priceWei) * amount;
        if (msg.value < totalPrice) revert InsufficientPayment();

        // Efectos
        project.minted += amount;

        // Interacciones
        _mint(msg.sender, projectId, amount, "");

        emit TokensMinted(projectId, msg.sender, amount, totalPrice);

        // Refund de exceso
        if (msg.value > totalPrice) {
            uint256 refund = msg.value - totalPrice;
            (bool success, ) = msg.sender.call{value: refund}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @notice Batch mint de múltiples proyectos en una transacción
     * @param projectIds Array de IDs de proyectos
     * @param amounts Array de cantidades correspondientes
     *
     * @dev Transacción atómica: o todos se mintean o ninguno
     */
    function mintBatch(
        uint256[] calldata projectIds,
        uint96[] calldata amounts
    ) external payable whenNotPaused nonReentrant {
        uint256 length = projectIds.length;
        if (length == 0 || length != amounts.length) revert InvalidAmount();

        uint256 totalCost;

        // Validar y calcular costo total
        for (uint256 i = 0; i < length; i++) {
            if (amounts[i] == 0) revert InvalidAmount();

            Project storage project = projects[projectIds[i]];

            if (!project.active) revert ProjectNotActive();
            if (project.minted + amounts[i] > project.totalSupply)
                revert ExceedsTotalSupply();

            uint256 cost = uint256(project.priceWei) * amounts[i];
            totalCost += cost;

            // Actualizar estado
            project.minted += amounts[i];

            emit TokensMinted(projectIds[i], msg.sender, amounts[i], cost);
        }

        if (msg.value < totalCost) revert InsufficientPayment();

        // Mintear batch
        _mintBatch(msg.sender, projectIds, _toUint256Array(amounts), "");

        // Refund exceso
        if (msg.value > totalCost) {
            uint256 refund = msg.value - totalCost;
            (bool success, ) = msg.sender.call{value: refund}("");
            if (!success) revert TransferFailed();
        }
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Obtener información completa del proyecto
     * @param projectId ID del proyecto
     * @return project Struct Project completo
     */
    function getProject(
        uint256 projectId
    ) external view returns (Project memory) {
        return projects[projectId];
    }

    /**
     * @notice Obtener métricas del proyecto
     * @param projectId ID del proyecto
     * @return metrics Struct Metrics completo
     */
    function getMetrics(
        uint256 projectId
    ) external view returns (Metrics memory) {
        return metrics[projectId];
    }

    /**
     * @notice Tokens disponibles para compra
     * @param projectId ID del proyecto
     * @return available Cantidad de tokens disponibles
     */
    function availableTokens(uint256 projectId) external view returns (uint96) {
        Project memory project = projects[projectId];
        return project.totalSupply - project.minted;
    }

    /**
     * @notice Verificar si un proyecto existe
     * @param projectId ID del proyecto
     * @return exists True si el proyecto existe
     */
    function projectExists(uint256 projectId) external view returns (bool) {
        return projects[projectId].totalSupply > 0;
    }

    /**
     * @notice Obtener el siguiente ID de proyecto que será creado
     * @return nextId Próximo ID de proyecto
     */
    function nextProjectId() external view returns (uint256) {
        return _nextProjectId;
    }

    /**
     * @notice URI de metadata del token
     * @param projectId ID del proyecto
     * @return URI completa del metadata
     *
     * @dev Formato: {baseURI}{projectId}
     * @dev baseURI puede ser:
     *      - Backend: "https://api.nikosun.com/metadata/" → "https://api.nikosun.com/metadata/1"
     *      - IPFS: "ipfs://QmHash/" → "ipfs://QmHash/1"
     *      - Gateway: "https://gateway.ipfs.io/ipfs/QmHash/" → "https://gateway.ipfs.io/ipfs/QmHash/1"
     */
    function uri(
        uint256 projectId
    ) public view override returns (string memory) {
        if (projects[projectId].totalSupply == 0) revert InvalidProject();

        return string(abi.encodePacked(baseURI, _toString(projectId)));
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @notice Pausar todas las operaciones de minting
     * @dev Solo en caso de emergencia
     * @dev No afecta transfers entre usuarios
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Reanudar operaciones
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Retirar fondos del contrato
     * @dev Solo admin, fondos de ventas de tokens
     */
    function withdraw() external onlyRole(ADMIN_ROLE) nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InvalidAmount();

        (bool success, ) = msg.sender.call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Retirar fondos a una dirección específica
     * @param recipient Dirección de destino
     */
    function withdrawTo(
        address payable recipient
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert Unauthorized();

        uint256 balance = address(this).balance;
        if (balance == 0) revert InvalidAmount();

        (bool success, ) = recipient.call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    // ============ INTERNAL HELPERS ============

    /**
     * @notice Convertir array de uint96 a uint256
     * @dev Necesario para _mintBatch que espera uint256[]
     */
    function _toUint256Array(
        uint96[] calldata input
    ) private pure returns (uint256[] memory) {
        uint256[] memory output = new uint256[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            output[i] = input[i];
        }
        return output;
    }

    /**
     * @notice Convertir uint256 a string
     * @dev Helper para construir URI
     */
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ============ OVERRIDES ============

    /**
     * @notice Override requerido para múltiple herencia
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Recibir SYS directamente
     */
    receive() external payable {}
}
