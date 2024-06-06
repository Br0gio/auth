import log from "@/next/log";
import { VerticallyCentered } from "@ente/shared/components/Container";
import EnteSpinner from "@ente/shared/components/EnteSpinner";
import HTTPService from "@ente/shared/network/HTTPService";
import { LS_KEYS, getData, setData } from "@ente/shared/storage/localStorage";
import { useRouter } from "next/router";
import { useEffect } from "react";

const AccountHandoff = () => {
    const router = useRouter();

    const retrieveAccountData = () => {
        try {
            extractAccountsToken();

            router.push("/passkeys");
        } catch (e) {
            log.error("Failed to deserialize and set passed user data", e);
            // Not much we can do here, but this redirect might be misleading.
            router.push("/login");
        }
    };

    const getClientPackageName = () => {
        const urlParams = new URLSearchParams(window.location.search);
        const pkg = urlParams.get("package");
        if (!pkg) return;
        setData(LS_KEYS.CLIENT_PACKAGE, { name: pkg });
        HTTPService.setHeaders({
            "X-Client-Package": pkg,
        });
    };

    const extractAccountsToken = () => {
        const urlParams = new URLSearchParams(window.location.search);
        const token = urlParams.get("token");
        if (!token) {
            throw new Error("token not found");
        }

        const user = getData(LS_KEYS.USER) || {};
        user.token = token;

        setData(LS_KEYS.USER, user);
    };

    useEffect(() => {
        getClientPackageName();
        retrieveAccountData();
    }, []);

    return (
        <VerticallyCentered>
            <EnteSpinner />
        </VerticallyCentered>
    );
};

export default AccountHandoff;
