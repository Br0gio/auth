import { Container } from "components/Container";
import { Spinner } from "components/Spinner";
import * as React from "react";

export default function DesktopRedirect() {
    React.useEffect(() => {
        const currentURL = new URL(window.location.href);
        const desktopRedirectURL = new URL("ente://app/gallery");
        desktopRedirectURL.search = currentURL.search;
        window.location.href = desktopRedirectURL.href;
    }, []);

    return (
        <Container>
            <Spinner />
        </Container>
    );
}