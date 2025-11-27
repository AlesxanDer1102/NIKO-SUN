// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script,console} from "forge-std/Script.sol";
import {SolarTokenV1} from "../src/SolarTokenV1.sol";

/**
 * @title DeploySolarToken
 * @notice Script simple para desplegar el contrato SolarTokenV1
 *
 */
contract DeploySolarToken is Script {
    // URI base por defecto - puedes cambiarlo aquí o via variable de entorno
    string public constant DEFAULT_BASE_URI =
        "https://api.nikosun.com/metadata/";

    function run() external {
        // Obtener base URI de variable de entorno o usar default
        string memory baseURI = vm.envOr("BASE_URI", DEFAULT_BASE_URI);

        // Obtener private key de variable de entorno

        // Log información
        console.log("===================================");
        console.log("Desplegando SolarTokenV1");
        console.log("===================================");
        console.log("Base URI:", baseURI);
        console.log("===================================");

        // Iniciar broadcast
        vm.startBroadcast();

        // Desplegar contrato
        SolarTokenV1 solarToken = new SolarTokenV1(baseURI);

        // Detener broadcast
        vm.stopBroadcast();

        // Log resultado
        console.log("===================================");
        console.log("SolarTokenV1 desplegado en:", address(solarToken));
        console.log("===================================");
        console.log("");
        console.log("Roles asignados al deployer:");
        console.log("- DEFAULT_ADMIN_ROLE");
        console.log("- ADMIN_ROLE");
        console.log("- MINTER_ROLE");
        console.log("- PAUSER_ROLE");
        console.log("===================================");
    }
}
